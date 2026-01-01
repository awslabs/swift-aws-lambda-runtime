//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright SwiftAWSLambdaRuntime project authors
// Copyright (c) Amazon.com, Inc. or its affiliates.
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AWSLambdaEvents
import AWSLambdaRuntime
import Logging
import PostgresNIO
import ServiceLifecycle

struct User: Codable {
    let id: Int
    let username: String
}

@main
struct LambdaFunction {

    private let pgClient: PostgresClient
    private let logger: Logger

    private init() throws {
        var logger = Logger(label: "ServiceLifecycleExample")
        logger.logLevel = Lambda.env("LOG_LEVEL").flatMap { .init(rawValue: $0) } ?? .info
        self.logger = logger

        self.pgClient = try LambdaFunction.createPostgresClient(
            host: Lambda.env("DB_HOST") ?? "localhost",
            user: Lambda.env("DB_USER") ?? "postgres",
            password: Lambda.env("DB_PASSWORD") ?? "secret",
            dbName: Lambda.env("DB_NAME") ?? "servicelifecycle",
            logger: self.logger
        )
    }

    /// Function entry point when the runtime environment is created
    private func main() async throws {

        // Instantiate LambdaRuntime with a handler implementing the business logic of the Lambda function
        let lambdaRuntime = LambdaRuntime(logger: self.logger, body: self.handler)

        // Use a prelude service to execute PG code before setting up the Lambda service
        // the PG code will run only once and will create the database schema and populate it with initial data
        let preludeService = PreludeService(
            service: lambdaRuntime,
            prelude: {
                try await prepareDatabase()
            }
        )

        /// Use ServiceLifecycle to manage the initialization and termination
        /// of the PGClient together with the LambdaRuntime
        let serviceGroup = ServiceGroup(
            services: [self.pgClient, preludeService],
            gracefulShutdownSignals: [.sigterm],
            cancellationSignals: [.sigint],
            logger: self.logger
        )

        // launch the service groups
        // this call will return upon termination or cancellation of all the services
        try await serviceGroup.run()

        // perform any cleanup here
    }

    /// Function handler. This code is called at each function invocation
    /// input event is ignored in this demo.
    private func handler(event: APIGatewayV2Request, context: LambdaContext) async throws -> APIGatewayV2Response {

        var result: [User] = []
        do {
            // IMPORTANT - CURRENTLY, THIS CALL STOPS WHEN DB IS NOT REACHABLE
            // See: https://github.com/vapor/postgres-nio/issues/489
            // This is why there is a timeout, as suggested Fabian
            // See: https://github.com/vapor/postgres-nio/issues/489#issuecomment-2186509773
            result = try await timeout(deadline: .seconds(3)) {
                // query users
                logger.trace("Querying database")
                return try await self.queryUsers()
            }
        } catch {
            logger.error("Database Error", metadata: ["cause": "\(String(reflecting: error))"])
        }

        return try .init(
            statusCode: .ok,
            headers: ["content-type": "application/json"],
            encodableBody: result
        )
    }

    /// Prepare the database
    /// At first run, this functions checks the database exist and is populated.
    /// This is useful for demo purposes. In real life, the database will contain data already.
    private func prepareDatabase() async throws {
        do {

            // initial creation of the table. This will fails if it already exists
            logger.trace("Testing if table exists")
            try await self.pgClient.query(SQLStatements.createTable)

            // it did not fail, it means the table is new and empty
            logger.trace("Populate table")
            try await self.pgClient.query(SQLStatements.populateTable)

        } catch is PSQLError {
            // when there is a database error, it means the table or values already existed
            // ignore this error
            logger.trace("Table exists already")
        } catch {
            // propagate other errors
            throw error
        }
    }

    /// Query the database
    private func queryUsers() async throws -> [User] {
        var users: [User] = []
        let query = SQLStatements.queryAllUsers
        let rows = try await self.pgClient.query(query)
        for try await (id, username) in rows.decode((Int, String).self) {
            self.logger.trace("\(id) : \(username)")
            users.append(User(id: id, username: username))
        }
        return users
    }

    /// Create a postgres client
    /// ...TODO
    private static func createPostgresClient(
        host: String,
        user: String,
        password: String,
        dbName: String,
        logger: Logger
    ) throws -> PostgresClient {

        // Load the root certificate
        let region = Lambda.env("AWS_REGION") ?? "us-east-1"
        guard let pem = rootRDSCertificates[region] else {
            logger.error("No root certificate found for the specified AWS region.")
            throw LambdaErrors.missingRootCertificateForRegion(region)
        }
        let certificatePEM = Array(pem.utf8)
        let rootCert = try NIOSSLCertificate.fromPEMBytes(certificatePEM)

        // Add the root certificate to the TLS configuration
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.trustRoots = .certificates(rootCert)

        // Enable full verification
        tlsConfig.certificateVerification = .fullVerification

        let config = PostgresClient.Configuration(
            host: host,
            port: 5432,
            username: user,
            password: password,
            database: dbName,
            tls: .prefer(tlsConfig)
        )

        return PostgresClient(configuration: config)
    }

    private struct SQLStatements {
        static let createTable: PostgresQuery =
            "CREATE TABLE users (id SERIAL PRIMARY KEY, username VARCHAR(50) NOT NULL);"
        static let populateTable: PostgresQuery = "INSERT INTO users (username) VALUES ('alice'), ('bob'), ('charlie');"
        static let queryAllUsers: PostgresQuery = "SELECT id, username FROM users"
    }

    static func main() async throws {
        try await LambdaFunction().main()
    }

}

public enum LambdaErrors: Error {
    case missingRootCertificateForRegion(String)
}

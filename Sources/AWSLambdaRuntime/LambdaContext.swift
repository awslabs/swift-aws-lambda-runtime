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

import Logging
import NIOCore
import ServiceContextModule

// MARK: - Client Context

/// AWS Mobile SDK client fields.
public struct ClientApplication: Codable, Sendable {
    /// The mobile app installation id
    public let installationID: String?
    /// The app title for the mobile app as registered with AWS' mobile services.
    public let appTitle: String?
    /// The version name of the application as registered with AWS' mobile services.
    public let appVersionName: String?
    /// The app version code.
    public let appVersionCode: String?
    /// The package name for the mobile application invoking the function
    public let appPackageName: String?

    private enum CodingKeys: String, CodingKey {
        case installationID = "installation_id"
        case appTitle = "app_title"
        case appVersionName = "app_version_name"
        case appVersionCode = "app_version_code"
        case appPackageName = "app_package_name"
    }

    public init(
        installationID: String? = nil,
        appTitle: String? = nil,
        appVersionName: String? = nil,
        appVersionCode: String? = nil,
        appPackageName: String? = nil
    ) {
        self.installationID = installationID
        self.appTitle = appTitle
        self.appVersionName = appVersionName
        self.appVersionCode = appVersionCode
        self.appPackageName = appPackageName
    }
}

/// For invocations from the AWS Mobile SDK, data about the client application and device.
public struct ClientContext: Codable, Sendable {
    /// Information about the mobile application invoking the function.
    public let client: ClientApplication?
    /// Custom properties attached to the mobile event context.
    public let custom: [String: String]?
    /// Environment settings from the mobile client.
    public let environment: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case client
        case custom
        case environment = "env"
    }

    public init(
        client: ClientApplication? = nil,
        custom: [String: String]? = nil,
        environment: [String: String]? = nil
    ) {
        self.client = client
        self.custom = custom
        self.environment = environment
    }
}

// MARK: - Context

/// Lambda runtime context.
/// The Lambda runtime generates and passes the `LambdaContext` to the Lambda handler as an argument.
@available(LambdaSwift 2.0, *)
public struct LambdaContext: CustomDebugStringConvertible, Sendable {

    // use a final class as storage to have value type semantic with
    // low overhead of class for copy on write operations
    // https://www.youtube.com/watch?v=iLDldae64xE
    final class _Storage: Sendable {
        let requestID: String
        let traceID: String
        let tenantID: String?
        let invokedFunctionARN: String
        let deadline: LambdaClock.Instant
        let cognitoIdentity: String?
        let clientContext: ClientContext?
        let logger: Logger

        init(
            requestID: String,
            traceID: String,
            tenantID: String?,
            invokedFunctionARN: String,
            deadline: LambdaClock.Instant,
            cognitoIdentity: String?,
            clientContext: ClientContext?,
            logger: Logger
        ) {
            self.requestID = requestID
            self.traceID = traceID
            self.tenantID = tenantID
            self.invokedFunctionARN = invokedFunctionARN
            self.deadline = deadline
            self.cognitoIdentity = cognitoIdentity
            self.clientContext = clientContext
            self.logger = logger
        }
    }

    private var storage: _Storage

    /// The request ID, which identifies the request that triggered the function invocation.
    public var requestID: String {
        self.storage.requestID
    }

    /// The AWS X-Ray tracing header.
    public var traceID: String {
        self.storage.traceID
    }

    /// The Tenant ID.
    public var tenantID: String? {
        self.storage.tenantID
    }

    /// The ARN of the Lambda function, version, or alias that's specified in the invocation.
    public var invokedFunctionARN: String {
        self.storage.invokedFunctionARN
    }

    /// The timestamp that the function times out.
    public var deadline: LambdaClock.Instant {
        self.storage.deadline
    }

    /// For invocations from the AWS Mobile SDK, data about the Amazon Cognito identity provider.
    public var cognitoIdentity: String? {
        self.storage.cognitoIdentity
    }

    /// For invocations from the AWS Mobile SDK, data about the client application and device.
    public var clientContext: ClientContext? {
        self.storage.clientContext
    }

    /// `Logger` to log with.
    ///
    /// - note: The `LogLevel` can be configured using the `LOG_LEVEL` environment variable.
    public var logger: Logger {
        self.storage.logger
    }

    @available(
        *,
        deprecated,
        message:
            "This method will be removed in a future major version update. Use init(requestID:traceID:tenantID:invokedFunctionARN:deadline:cognitoIdentity:clientContext:logger) instead."
    )
    public init(
        requestID: String,
        traceID: String,
        invokedFunctionARN: String,
        deadline: LambdaClock.Instant,
        cognitoIdentity: String? = nil,
        clientContext: ClientContext? = nil,
        logger: Logger
    ) {
        self.init(
            requestID: requestID,
            traceID: traceID,
            tenantID: nil,
            invokedFunctionARN: invokedFunctionARN,
            deadline: deadline,
            cognitoIdentity: cognitoIdentity,
            clientContext: clientContext,
            logger: logger
        )
    }
    public init(
        requestID: String,
        traceID: String,
        tenantID: String?,
        invokedFunctionARN: String,
        deadline: LambdaClock.Instant,
        cognitoIdentity: String? = nil,
        clientContext: ClientContext? = nil,
        logger: Logger
    ) {
        self.storage = _Storage(
            requestID: requestID,
            traceID: traceID,
            tenantID: tenantID,
            invokedFunctionARN: invokedFunctionARN,
            deadline: deadline,
            cognitoIdentity: cognitoIdentity,
            clientContext: clientContext,
            logger: logger
        )
    }

    public func getRemainingTime() -> Duration {
        let deadline = self.deadline
        return LambdaClock().now.duration(to: deadline)
    }

    public var debugDescription: String {
        "\(Self.self)(requestID: \(self.requestID), traceID: \(self.traceID), invokedFunctionARN: \(self.invokedFunctionARN), cognitoIdentity: \(self.cognitoIdentity ?? "nil"), clientContext: \(String(describing: self.clientContext)), deadline: \(self.deadline))"
    }

    /// This interface is not part of the public API and must not be used by adopters. This API is not part of semver versioning.
    /// The timeout is expressed relative to now
    package static func __forTestsOnly(
        requestID: String,
        traceID: String,
        tenantID: String?,
        invokedFunctionARN: String,
        timeout: Duration,
        logger: Logger
    ) -> LambdaContext {
        LambdaContext(
            requestID: requestID,
            traceID: traceID,
            tenantID: tenantID,
            invokedFunctionARN: invokedFunctionARN,
            deadline: LambdaClock().now.advanced(by: timeout),
            logger: logger
        )
    }
}

// MARK: - ServiceContext integration

/// A ``ServiceContextKey`` for the AWS X-Ray trace ID.
///
/// This allows downstream libraries that depend on `swift-service-context`
/// (but not on `AWSLambdaRuntime`) to access the current trace ID via
/// `ServiceContext.current?.traceID`.
private enum LambdaTraceIDKey: ServiceContextKey {
    typealias Value = String
    static var nameOverride: String? { AmazonHeaders.traceID }
}

extension ServiceContext {
    /// The AWS X-Ray trace ID for the current Lambda invocation, if available.
    ///
    /// This value is automatically set by the Lambda runtime before calling the handler
    /// and is available to all code running within the handler's async task tree.
    ///
    /// Downstream libraries can read this without depending on `AWSLambdaRuntime`:
    /// ```swift
    /// if let traceID = ServiceContext.current?.traceID {
    ///     // propagate traceID to outgoing HTTP requests, etc.
    /// }
    /// ```
    public var traceID: String? {
        get {
            self[LambdaTraceIDKey.self]
        }
        set {
            self[LambdaTraceIDKey.self] = newValue
        }
    }
}

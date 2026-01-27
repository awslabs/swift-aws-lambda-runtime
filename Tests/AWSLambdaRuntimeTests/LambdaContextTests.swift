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

import Foundation
import Logging
import Testing

@testable import AWSLambdaRuntime

@Suite("LambdaContext ClientContext Tests")
struct LambdaContextTests {

    @Test("ClientContext with full data resolves correctly")
    func clientContextWithFullDataResolves() throws {
        let custom = ["key": "value"]
        let environment = ["key": "value"]
        let clientContext = ClientContext(
            client: ClientApplication(
                installationID: "test-id",
                appTitle: "test-app",
                appVersionName: "1.0",
                appVersionCode: "100",
                appPackageName: "com.test.app"
            ),
            custom: custom,
            environment: environment
        )

        let encoder = JSONEncoder()
        let clientContextData = try encoder.encode(clientContext)

        // Verify JSON encoding/decoding works correctly
        let decoder = JSONDecoder()
        let decodedClientContext = try decoder.decode(ClientContext.self, from: clientContextData)

        let decodedClient = try #require(decodedClientContext.client)
        let originalClient = try #require(clientContext.client)

        #expect(decodedClient.installationID == originalClient.installationID)
        #expect(decodedClient.appTitle == originalClient.appTitle)
        #expect(decodedClient.appVersionName == originalClient.appVersionName)
        #expect(decodedClient.appVersionCode == originalClient.appVersionCode)
        #expect(decodedClient.appPackageName == originalClient.appPackageName)
        #expect(decodedClientContext.custom == clientContext.custom)
        #expect(decodedClientContext.environment == clientContext.environment)
    }

    @Test("ClientContext with empty data resolves correctly")
    func clientContextWithEmptyDataResolves() throws {
        let emptyClientContextJSON = "{}"
        let emptyClientContextData = emptyClientContextJSON.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decodedClientContext = try decoder.decode(ClientContext.self, from: emptyClientContextData)

        // With empty JSON, we expect nil values for optional fields
        #expect(decodedClientContext.client == nil)
        #expect(decodedClientContext.custom == nil)
        #expect(decodedClientContext.environment == nil)
    }

    @Test("ClientContext with AWS Lambda JSON payload decodes correctly")
    func clientContextWithAWSLambdaJSONPayload() throws {
        let jsonPayload = """
            {
              "client": {
                "installation_id": "example-id",
                "app_title": "Example App",
                "app_version_name": "1.0",
                "app_version_code": "1",
                "app_package_name": "com.example.app"
              },
              "custom": {
                "customKey": "customValue"
              },
              "env": {
                "platform": "Android",
                "platform_version": "10"
              }
            }
            """

        let jsonData = jsonPayload.data(using: .utf8)!
        let decoder = JSONDecoder()
        let decodedClientContext = try decoder.decode(ClientContext.self, from: jsonData)

        // Verify client application data
        let client = try #require(decodedClientContext.client)
        #expect(client.installationID == "example-id")
        #expect(client.appTitle == "Example App")
        #expect(client.appVersionName == "1.0")
        #expect(client.appVersionCode == "1")
        #expect(client.appPackageName == "com.example.app")

        // Verify custom properties
        let custom = try #require(decodedClientContext.custom)
        #expect(custom["customKey"] == "customValue")

        // Verify environment settings
        let environment = try #require(decodedClientContext.environment)
        #expect(environment["platform"] == "Android")
        #expect(environment["platform_version"] == "10")
    }

    @Test("getRemainingTime returns positive duration for future deadline")
    @available(LambdaSwift 2.0, *)
    func getRemainingTimeReturnsPositiveDurationForFutureDeadline() {

        // Create context with deadline 30 seconds in the future
        let context = LambdaContext.__forTestsOnly(
            requestID: "test-request",
            traceID: "test-trace",
            tenantID: nil,
            invokedFunctionARN: "test-arn",
            timeout: .seconds(30),
            logger: Logger(label: "test")
        )

        // Get remaining time - should be positive since deadline is in future
        let remainingTime = context.getRemainingTime()

        // Verify Duration can be negative (not absolute value)
        #expect(remainingTime > .zero, "getRemainingTime() should return positive duration when deadline is in future")
        #expect(remainingTime <= Duration.seconds(31), "Remaining time should be approximately 30 seconds")
        #expect(remainingTime >= Duration.seconds(-29), "Remaining time should be approximately -30 seconds")
    }
}

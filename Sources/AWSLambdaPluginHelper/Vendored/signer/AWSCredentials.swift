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

//
//  credentials.swift
//  aws-sign
//
//  Created by Adam Fowler on 29/08/2019.
//
import class Foundation.ProcessInfo

/// Protocol for providing credential details for accessing AWS services
public protocol Credential {
    var accessKeyId: String { get }
    var secretAccessKey: String { get }
    var sessionToken: String? { get }
}

/// basic version of Credential where you supply the credentials
public struct StaticCredential: Credential {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?

    public init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}

/// environment variable version of credential that uses system environment variables to get credential details
public struct EnvironmentCredential: Credential {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?

    public init?() {
        guard let accessKeyId = ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] else {
            return nil
        }
        guard let secretAccessKey = ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"] else {
            return nil
        }
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = ProcessInfo.processInfo.environment["AWS_SESSION_TOKEN"]
    }
}

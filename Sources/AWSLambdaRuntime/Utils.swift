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

import NIOConcurrencyHelpers
import NIOPosix

// import Synchronization

enum Consts {
    static let apiPrefix = "/2018-06-01"
    static let invocationURLPrefix = "\(apiPrefix)/runtime/invocation"
    static let getNextInvocationURLSuffix = "/next"
    static let postResponseURLSuffix = "/response"
    static let postErrorURLSuffix = "/error"
    static let postInitErrorURL = "\(apiPrefix)/runtime/init/error"
    static let initializationError = "InitializationError"
}

/// AWS Lambda HTTP Headers, used to populate the `LambdaContext` object. E.g.
/// Content-Type: application/json;
/// Lambda-Runtime-Aws-Request-Id: bfcc9017-7f34-4154-9699-ff0229e9ad2b;
/// Lambda-Runtime-Aws-Tenant-Id: seb;
/// Lambda-Runtime-Deadline-Ms: 1763672952393;
/// Lambda-Runtime-Invoked-Function-Arn: arn:aws:lambda:us-west-2:486652066693:function:MultiTenant-MultiTenantLambda-1E9mgLUtIQ9N;
/// Lambda-Runtime-Trace-Id: Root=1-691f833c-79cf6a2b23942f8925881714;Parent=76ab2f41125eef94;Sampled=0;Lineage=1:9581a8d4:0; Date: Thu, 20 Nov 2025 21:08:12 GMT; Transfer-Encoding: chunked
enum AmazonHeaders {
    static let requestID = "Lambda-Runtime-Aws-Request-Id"
    static let traceID = "Lambda-Runtime-Trace-Id"
    static let clientContext = "X-Amz-Client-Context"
    static let cognitoIdentity = "X-Amz-Cognito-Identity"
    static let deadline = "Lambda-Runtime-Deadline-Ms"
    static let invokedFunctionARN = "Lambda-Runtime-Invoked-Function-Arn"
    static let tenantID = "Lambda-Runtime-Aws-Tenant-Id"
}

extension String {
    func encodeAsJSONString(into bytes: inout [UInt8]) {
        bytes.append(UInt8(ascii: "\""))
        let stringBytes = self.utf8
        var startCopyIndex = stringBytes.startIndex
        var nextIndex = startCopyIndex

        while nextIndex != stringBytes.endIndex {
            switch stringBytes[nextIndex] {
            case 0..<32, UInt8(ascii: "\""), UInt8(ascii: "\\"):
                // All Unicode characters may be placed within the
                // quotation marks, except for the characters that MUST be escaped:
                // quotation mark, reverse solidus, and the control characters (U+0000
                // through U+001F).
                // https://tools.ietf.org/html/rfc7159#section-7

                // copy the current range over
                bytes.append(contentsOf: stringBytes[startCopyIndex..<nextIndex])
                bytes.append(UInt8(ascii: "\\"))
                bytes.append(stringBytes[nextIndex])

                nextIndex = stringBytes.index(after: nextIndex)
                startCopyIndex = nextIndex
            default:
                nextIndex = stringBytes.index(after: nextIndex)
            }
        }

        // copy everything, that hasn't been copied yet
        bytes.append(contentsOf: stringBytes[startCopyIndex..<nextIndex])
        bytes.append(UInt8(ascii: "\""))
    }
}

@available(LambdaSwift 2.0, *)
extension AmazonHeaders {
    /// Generates (X-Ray) trace ID.
    /// # Trace ID Format
    /// A `trace_id` consists of three numbers separated by hyphens.
    /// For example, `1-58406520-a006649127e371903a2de979`. This includes:
    /// - The version number, that is, 1.
    /// - The time of the original request, in Unix epoch time, in **8 hexadecimal digits**.
    /// For example, 10:00AM December 1st, 2016 PST in epoch time is `1480615200` seconds, or `58406520` in hexadecimal digits.
    /// - A 96-bit identifier for the trace, globally unique, in **24 hexadecimal digits**.
    /// # References
    /// - [Generating trace IDs](https://docs.aws.amazon.com/xray/latest/devguide/xray-api-sendingdata.html#xray-api-traceids)
    /// - [Tracing header](https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html#xray-concepts-tracingheader)
    static func generateXRayTraceID() -> String {
        // The version number, that is, 1.
        let version: UInt = 1
        // The time of the original request, in Unix epoch time, in 8 hexadecimal digits.
        let now = UInt32(LambdaClock().now.millisecondsSinceEpoch() / 1000)
        let dateValue = String(now, radix: 16, uppercase: false)
        let datePadding = String(repeating: "0", count: max(0, 8 - dateValue.count))
        // A 96-bit identifier for the trace, globally unique, in 24 hexadecimal digits.
        let identifier =
            String(UInt64.random(in: UInt64.min...UInt64.max) | 1 << 63, radix: 16, uppercase: false)
            + String(UInt32.random(in: UInt32.min...UInt32.max) | 1 << 31, radix: 16, uppercase: false)
        return "\(version)-\(datePadding)\(dateValue)-\(identifier)"
    }
}

/// Temporary storage for value being sent from one isolation domain to another
// use NIOLockedValueBox instead of Mutex to avoid compiler crashes on 6.0
// see https://github.com/swiftlang/swift/issues/78048
@usableFromInline
struct SendingStorage<Value>: ~Copyable, @unchecked Sendable {
    @usableFromInline
    struct ValueAlreadySentError: Error {
        @usableFromInline
        init() {}
    }

    @usableFromInline
    // let storage: Mutex<Value?>
    let storage: NIOLockedValueBox<Value?>

    @inlinable
    init(_ value: sending Value) {
        self.storage = .init(value)
    }

    @inlinable
    func get() throws -> Value {
        // try self.storage.withLock {
        try self.storage.withLockedValue {
            guard let value = $0 else { throw ValueAlreadySentError() }
            $0 = nil
            return value
        }
    }
}

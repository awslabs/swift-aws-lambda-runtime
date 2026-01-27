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
import Testing

@testable import AWSLambdaPluginHelper

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite
struct SignerTests {
    let credentials: Credential = StaticCredential(accessKeyId: "MYACCESSKEY", secretAccessKey: "MYSECRETACCESSKEY")

    @Test
    func testSignGetHeaders() {
        let signer = AWSSigner(credentials: credentials, name: "glacier", region: "us-east-1")
        let headers = signer.signHeaders(
            url: URL(string: "https://glacier.us-east-1.amazonaws.com/-/vaults")!,
            method: .GET,
            headers: ["x-amz-glacier-version": "2012-06-01"],
            date: Date(timeIntervalSinceReferenceDate: 2_000_000)
        )
        #expect(
            headers["Authorization"].first
                == "AWS4-HMAC-SHA256 Credential=MYACCESSKEY/20010124/us-east-1/glacier/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date;x-amz-glacier-version, Signature=acfa9b03fca6b098d7b88bfd9bbdb4687f5b34e944a9c6ed9f4814c1b0b06d62"
        )
    }

    @Test
    func testSignPutHeaders() {
        let signer = AWSSigner(credentials: credentials, name: "sns", region: "eu-west-1")
        let headers = signer.signHeaders(
            url: URL(string: "https://sns.eu-west-1.amazonaws.com/")!,
            method: .POST,
            headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"],
            body: .string("Action=ListTopics&Version=2010-03-31"),
            date: Date(timeIntervalSinceReferenceDate: 200)
        )
        #expect(
            headers["Authorization"].first
                == "AWS4-HMAC-SHA256 Credential=MYACCESSKEY/20010101/eu-west-1/sns/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=1d29943055a8ad094239e8de06082100f2426ebbb2c6a5bbcbb04c63e6a3f274"
        )
    }

    @Test
    func testSignS3GetURL() {
        let signer = AWSSigner(credentials: credentials, name: "s3", region: "us-east-1")
        let url = signer.signURL(
            url: URL(string: "https://s3.us-east-1.amazonaws.com/")!,
            method: .GET,
            date: Date(timeIntervalSinceReferenceDate: 100000)
        )
        #expect(
            url.absoluteString
                == "https://s3.us-east-1.amazonaws.com/?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MYACCESSKEY%2F20010102%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20010102T034640Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=27957103c8bfdff3560372b1d85976ed29c944f34295eca2d4fdac7fc02c375a"
        )
    }

    @Test
    func testSignS3PutURL() {
        let signer = AWSSigner(credentials: credentials, name: "s3", region: "eu-west-1")
        let url = signer.signURL(
            url: URL(string: "https://test-bucket.s3.amazonaws.com/test-put.txt")!,
            method: .PUT,
            body: .string("Testing signed URLs"),
            date: Date(timeIntervalSinceReferenceDate: 100000)
        )
        #expect(
            url.absoluteString
                == "https://test-bucket.s3.amazonaws.com/test-put.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MYACCESSKEY%2F20010102%2Feu-west-1%2Fs3%2Faws4_request&X-Amz-Date=20010102T034640Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=13d665549a6ea5eb6a1615ede83440eaed3e0ee25c964e62d188c896d916d96f"
        )
    }
}

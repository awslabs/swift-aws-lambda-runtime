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

let functionWithUrlTemplate = #"""
    import AWSLambdaRuntime
    import AWSLambdaEvents

    // in this example we receive a FunctionURLRequest and we return a FunctionURLResponse
    // https://docs.aws.amazon.com/lambda/latest/dg/urls-invocation.html#urls-payloads

    let runtime = LambdaRuntime {
            (event: FunctionURLRequest, context: LambdaContext) -> FunctionURLResponse in
            
            guard let name = event.queryStringParameters?["name"] else {
                return FunctionURLResponse(statusCode: .badRequest)
            }

    		return FunctionURLResponse(statusCode: .ok, body: #"{ "message" : "Hello \#\#(name)" } "#)
    }

    try await runtime.run()
    """#

let functionWithJSONTemplate = #"""
    import AWSLambdaRuntime

    // the data structure to represent the input parameter
    struct HelloRequest: Decodable {
        let name: String
        let age: Int
    }

    // the data structure to represent the output response
    struct HelloResponse: Encodable {
        let greetings: String
    }

    // in this example we receive a HelloRequest JSON and we return a HelloResponse JSON    

    // the Lambda runtime
    let runtime = LambdaRuntime {
        (event: HelloRequest, context: LambdaContext) in

        HelloResponse(
            greetings: "Hello \(event.name). You look \(event.age > 30 ? "younger" : "older") than your age."
        )
    }

    // start the loop
    try await runtime.run()    
    """#

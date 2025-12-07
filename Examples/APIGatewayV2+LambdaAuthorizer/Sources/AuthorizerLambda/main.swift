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

//
// This is an example of a policy authorizer that always authorizes the request.
// The policy authorizer returns an IAM policy document that defines what the Lambda function caller can do and optional context key-value pairs
//
// This code is shown for the example only and is not used in this demo.
// This code doesn't perform any type of token validation. It should be used as a reference only.
let policyAuthorizerHandler:
    (APIGatewayLambdaAuthorizerRequest, LambdaContext) async throws -> APIGatewayLambdaAuthorizerPolicyResponse = {
        (request: APIGatewayLambdaAuthorizerRequest, context: LambdaContext) in

        context.logger.debug("+++ Policy Authorizer called +++")

        // typically, this function will check the validity of the incoming token received in the request

        // then it creates and returns a response
        return APIGatewayLambdaAuthorizerPolicyResponse(
            principalId: "John Appleseed",

            // this policy allows the caller to invoke any API Gateway endpoint
            policyDocument: .init(statement: [
                .init(
                    action: "execute-api:Invoke",
                    effect: .allow,
                    resource: "*"
                )

            ]),

            // this is additional context we want to return to the caller
            context: [
                "abc1": "xyz1",
                "abc2": "xyz2",
            ]
        )
    }

//
// This is an example of a simple authorizer that always authorizes the request.
// A simple authorizer returns a yes/no decision and optional context key-value pairs
//
// This code doesn't perform any type of token validation. It should be used as a reference only.
let simpleAuthorizerHandler:
    @Sendable (APIGatewayLambdaAuthorizerRequest, LambdaContext) async throws ->
        APIGatewayLambdaAuthorizerSimpleResponse = {
            (_: APIGatewayLambdaAuthorizerRequest, context: LambdaContext) in

            context.logger.debug("+++ Simple Authorizer called +++")

            // typically, this function will check the validity of the incoming token received in the request

            return APIGatewayLambdaAuthorizerSimpleResponse(
                // this is the authorization decision: yes or no
                isAuthorized: true,

                // this is additional context we want to return to the caller
                context: ["abc1": "xyz1"]
            )
        }

// create the runtime and start polling for new events.
// in this demo we use the simple authorizer handler
let runtime = LambdaRuntime(body: simpleAuthorizerHandler)
try await runtime.run()

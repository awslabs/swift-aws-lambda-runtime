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

import AWSLambdaRuntime

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

let tenants = TenantDataStore()

struct TenantMessage: Codable {
    let message: String
}

enum TenantError: Error {
    case missingTenantID
}

struct SimpleTenantHandler: LambdaHandler {
    typealias Event = TenantMessage
    typealias Output = TenantData

    let tenants: TenantDataStore

    func handle(_ event: TenantMessage, context: LambdaContext) async throws -> TenantData {
        guard let tenantID = context.tenantID else {
            throw TenantError.missingTenantID
        }

        let currentData = await tenants[tenantID] ?? TenantData(tenantID: tenantID)
        let updatedData = currentData.addingRequest(message: event.message)
        await tenants.update(id: tenantID, data: updatedData)
        return updatedData
    }
}

let handler = SimpleTenantHandler(tenants: tenants)
let runtime = LambdaRuntime(handler: LambdaCodableAdapter(handler: LambdaHandlerAdapter(handler: handler)))

try await runtime.run()

actor TenantDataStore {
    private var tenants: [String: TenantData] = [:]

    subscript(id: String) -> TenantData? {
        tenants[id]
    }

    // subscript setters can't be called from outside of the actor
    func update(id: String, data: TenantData) {
        tenants[id] = data
    }
}

struct TenantData: Codable {
    struct TenantRequest: Codable {
        let requestNumber: Int
        let timestamp: String
        let message: String
    }

    let tenantID: String
    let requestCount: Int
    let firstRequest: String
    let requests: [TenantRequest]

    init(tenantID: String) {
        self.init(
            tenantID: tenantID,
            requestCount: 0,
            firstRequest: "\(Date().timeIntervalSince1970)",
            requests: []
        )
    }

    func addingRequest(message: String) -> TenantData {
        let newCount = requestCount + 1
        let newRequest = TenantRequest(
            requestNumber: newCount,
            timestamp: "\(Date().timeIntervalSince1970)",
            message: message
        )
        return TenantData(
            tenantID: tenantID,
            requestCount: newCount,
            firstRequest: firstRequest,
            requests: requests + [newRequest]
        )
    }

    private init(
        tenantID: String,
        requestCount: Int,
        firstRequest: String,
        requests: [TenantRequest]
    ) {
        self.tenantID = tenantID
        self.requestCount = requestCount
        self.firstRequest = firstRequest
        self.requests = requests
    }
}

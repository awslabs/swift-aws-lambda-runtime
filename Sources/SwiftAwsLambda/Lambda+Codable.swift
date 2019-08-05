//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAwsLambda open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftAwsLambda project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAwsLambda project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

/// Extension to the `Lambda` companion to enable execution of Lambdas that take and return `Codable` payloads.
/// This is the most common way to use this library in AWS Lambda, since its JSON based.
extension Lambda {
    /// Run a Lambda defined by implementing the `LambdaCodableClosure` closure, having `In` and `Out` extending `Decodable` and `Encodable` respectively.
    ///
    /// - note: This is a blocking operation that will run forever, as it's lifecycle is managed by the AWS Lambda Runtime Engine.
    public static func run<In: Decodable, Out: Encodable>(_ closure: @escaping LambdaCodableClosure<In, Out>) {
        self.run(LambdaClosureWrapper(closure))
    }

    /// Run a Lambda defined by implementing the `LambdaCodableHandler` protocol, having `In` and `Out` are `Decodable` and `Encodable` respectively.
    ///
    /// - note: This is a blocking operation that will run forever, as it's lifecycle is managed by the AWS Lambda Runtime Engine.
    public static func run<Handler>(_ handler: Handler) where Handler: LambdaCodableHandler {
        self.run(handler as LambdaHandler)
    }

    // for testing
    internal static func run<In: Decodable, Out: Encodable>(maxTimes: Int = 0, _ closure: @escaping LambdaCodableClosure<In, Out>) -> LambdaLifecycleResult {
        return self.run(handler: LambdaClosureWrapper(closure), maxTimes: maxTimes)
    }

    // for testing
    internal static func run<Handler>(handler: Handler, maxTimes: Int = 0) -> LambdaLifecycleResult where Handler: LambdaCodableHandler {
        return self.run(handler: handler as LambdaHandler, maxTimes: maxTimes)
    }
}

/// A result type for a Lambda that returns a generic `Out`, having `Out` extend `Encodable`.
public typealias LambdaCodableResult<Out> = Result<Out, Error>

/// A callback for a Lambda that returns a `LambdaCodableResult<Out>` result type, having `Out` extend `Encodable`.
public typealias LambdaCodableCallback<Out> = (LambdaCodableResult<Out>) -> Void

/// A processing closure for a Lambda that takes an `In` and returns an `Out` via `LambdaCodableCallback<Out>` asynchronously,
/// having `In` and `Out` extending `Decodable` and `Encodable` respectively.
public typealias LambdaCodableClosure<In, Out> = (LambdaContext, In, LambdaCodableCallback<Out>) -> Void

/// A processing protocol for a Lambda that takes an `In` and returns an `Out` via `LambdaCodableCallback<Out>` asynchronously,
/// having `In` and `Out` extending `Decodable` and `Encodable` respectively.
public protocol LambdaCodableHandler: LambdaHandler {
    associatedtype In: Decodable
    associatedtype Out: Encodable

    func handle(context: LambdaContext, payload: In, callback: @escaping LambdaCodableCallback<Out>)
    var codec: LambdaCodableCodec<In, Out> { get }
}

/// Default implementation for `LambdaCodableHandler` codec which uses JSON via `LambdaCodableJsonCodec`.
/// Advanced users that want to inject their own codec can do it by overriding this.
public extension LambdaCodableHandler {
    var codec: LambdaCodableCodec<In, Out> {
        return LambdaCodableJsonCodec<In, Out>()
    }
}

/// LambdaCodableCodec is an abstract/empty implementation for codec which does `Encodable` -> `[UInt8]` encoding and `[UInt8]` -> `Decodable' decoding.
// TODO: would be nicer to use a protocol instead of this "abstract class", but generics get in the way
public class LambdaCodableCodec<In: Decodable, Out: Encodable> {
    func encode(_: Out) -> Result<[UInt8], Error> { fatalError("not implmented") }
    func decode(_: [UInt8]) -> Result<In, Error> { fatalError("not implmented") }
}

/// Default implementation of `Encodable` -> `[UInt8]` encoding and `[UInt8]` -> `Decodable' decoding
public extension LambdaCodableHandler {
    func handle(context: LambdaContext, payload: [UInt8], callback: @escaping (LambdaResult) -> Void) {
        switch self.codec.decode(payload) {
        case .failure(let error):
            return callback(.failure(Errors.requestDecoding(error)))
        case .success(let payloadAsCodable):
            self.handle(context: context, payload: payloadAsCodable) { result in
                switch result {
                case .failure(let error):
                    return callback(.failure(error))
                case .success(let encodable):
                    switch self.codec.encode(encodable) {
                    case .failure(let error):
                        return callback(.failure(Errors.responseEncoding(error)))
                    case .success(let codableAsBytes):
                        return callback(.success(codableAsBytes))
                    }
                }
            }
        }
    }
}

/// LambdaCodableJsonCodec is an implementation of `LambdaCodableCodec` which does `Encodable` -> `[UInt8]` encoding and `[UInt8]` -> `Decodable' decoding
/// using JSONEncoder and JSONDecoder respectively.
// This is a class as encoder amd decoder are a class, which means its cheaper to hold a reference to both in a class then a struct.
private class LambdaCodableJsonCodec<In: Decodable, Out: Encodable>: LambdaCodableCodec<In, Out> {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public override func encode(_ value: Out) -> Result<[UInt8], Error> {
        do {
            return .success(try [UInt8](self.encoder.encode(value)))
        } catch {
            return .failure(error)
        }
    }

    public override func decode(_ data: [UInt8]) -> Result<In, Error> {
        do {
            return .success(try self.decoder.decode(In.self, from: Data(data)))
        } catch {
            return .failure(error)
        }
    }
}

private struct LambdaClosureWrapper<In: Decodable, Out: Encodable>: LambdaCodableHandler {
    typealias Codec = LambdaCodableJsonCodec<In, Out>

    private let closure: LambdaCodableClosure<In, Out>
    init(_ closure: @escaping LambdaCodableClosure<In, Out>) {
        self.closure = closure
    }

    public func handle(context: LambdaContext, payload: In, callback: @escaping LambdaCodableCallback<Out>) {
        self.closure(context, payload, callback)
    }
}

private enum Errors: Error {
    case responseEncoding(Error)
    case requestDecoding(Error)
}

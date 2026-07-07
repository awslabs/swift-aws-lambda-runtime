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

import NIOCore

// This is heavily inspired by:
// https://github.com/swift-extras/swift-extras-uuid

struct LambdaRequestID {
    typealias uuid_t = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var uuid: uuid_t {
        self._uuid
    }

    static let null: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    /// Creates a random [v4](https://tools.ietf.org/html/rfc4122#section-4.1.3) UUID.
    init() {
        self = Self.generateRandom()
    }

    init?(uuidString: String) {
        guard uuidString.utf8.count == 36 else {
            return nil
        }

        if let requestID = uuidString.utf8.withContiguousStorageIfAvailable({ ptr -> LambdaRequestID? in
            let rawBufferPointer = UnsafeRawBufferPointer(ptr)
            let requestID = Self.fromPointer(rawBufferPointer)
            return requestID
        }) {
            if let requestID = requestID {
                self = requestID
            } else {
                return nil
            }
        } else {
            var newSwiftCopy = uuidString
            newSwiftCopy.makeContiguousUTF8()
            if let value = Self(uuidString: newSwiftCopy) {
                self = value
            } else {
                return nil
            }
        }
    }

    /// Creates a UUID from a `uuid_t`.
    init(uuid: uuid_t) {
        self._uuid = uuid
    }

    private let _uuid: uuid_t

    /// Returns a string representation for the `LambdaRequestID`, such as "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    var uuidString: String {
        self.uppercased
    }

    /// Returns a lowercase string representation for the `LambdaRequestID`, such as "e621e1f8-c36c-495a-93fc-0c247a3e6e5f"
    var lowercased: String {
        var bytes = self.toAsciiBytesOnStack(characters: Self.lowercaseLookup)
        return withUnsafeBytes(of: &bytes) {
            String(decoding: $0, as: Unicode.UTF8.self)
        }
    }

    /// Returns an uppercase string representation for the `LambdaRequestID`, such as "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    var uppercased: String {
        var bytes = self.toAsciiBytesOnStack(characters: Self.uppercaseLookup)
        return withUnsafeBytes(of: &bytes) {
            String(decoding: $0, as: Unicode.UTF8.self)
        }
    }

    /// thread safe secure random number generator.
    private static func generateRandom() -> Self {
        var generator = SystemRandomNumberGenerator()

        var _uuid: uuid_t = LambdaRequestID.null
        // https://tools.ietf.org/html/rfc4122#page-14
        // o  Set all the other bits to randomly (or pseudo-randomly) chosen
        //    values.
        withUnsafeMutableBytes(of: &_uuid) { ptr in
            ptr.storeBytes(of: generator.next(), toByteOffset: 0, as: UInt64.self)
            ptr.storeBytes(of: generator.next(), toByteOffset: 8, as: UInt64.self)
        }

        // o  Set the four most significant bits (bits 12 through 15) of the
        //    time_hi_and_version field to the 4-bit version number from
        //    Section 4.1.3.
        _uuid.6 = (_uuid.6 & 0x0F) | 0x40

        // o  Set the two most significant bits (bits 6 and 7) of the
        //    clock_seq_hi_and_reserved to zero and one, respectively.
        _uuid.8 = (_uuid.8 & 0x3F) | 0x80
        return LambdaRequestID(uuid: _uuid)
    }
}

// MARK: - Protocol extensions -

extension LambdaRequestID: Equatable {
    // sadly no auto conformance from the compiler
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs._uuid.0 == rhs._uuid.0 && lhs._uuid.1 == rhs._uuid.1 && lhs._uuid.2 == rhs._uuid.2
            && lhs._uuid.3 == rhs._uuid.3 && lhs._uuid.4 == rhs._uuid.4 && lhs._uuid.5 == rhs._uuid.5
            && lhs._uuid.6 == rhs._uuid.6 && lhs._uuid.7 == rhs._uuid.7 && lhs._uuid.8 == rhs._uuid.8
            && lhs._uuid.9 == rhs._uuid.9 && lhs._uuid.10 == rhs._uuid.10 && lhs._uuid.11 == rhs._uuid.11
            && lhs._uuid.12 == rhs._uuid.12 && lhs._uuid.13 == rhs._uuid.13 && lhs._uuid.14 == rhs._uuid.14
            && lhs._uuid.15 == rhs._uuid.15
    }
}

extension LambdaRequestID: Hashable {
    func hash(into hasher: inout Hasher) {
        var value = self._uuid
        withUnsafeBytes(of: &value) { ptr in
            hasher.combine(bytes: ptr)
        }
    }
}

extension LambdaRequestID: CustomStringConvertible {
    var description: String {
        self.uuidString
    }
}

extension LambdaRequestID: CustomDebugStringConvertible {
    var debugDescription: String {
        self.uuidString
    }
}

extension LambdaRequestID: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let uuidString = try container.decode(String.self)

        guard let uuid = LambdaRequestID.fromString(uuidString) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Attempted to decode UUID from invalid UUID string."
            )
        }

        self = uuid
    }
}

extension LambdaRequestID: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.uuidString)
    }
}

// MARK: - Implementation details -

extension LambdaRequestID {
    fileprivate static let lowercaseLookup: [UInt8] = [
        UInt8(ascii: "0"), UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"),
        UInt8(ascii: "4"), UInt8(ascii: "5"), UInt8(ascii: "6"), UInt8(ascii: "7"),
        UInt8(ascii: "8"), UInt8(ascii: "9"), UInt8(ascii: "a"), UInt8(ascii: "b"),
        UInt8(ascii: "c"), UInt8(ascii: "d"), UInt8(ascii: "e"), UInt8(ascii: "f"),
    ]

    fileprivate static let uppercaseLookup: [UInt8] = [
        UInt8(ascii: "0"), UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"),
        UInt8(ascii: "4"), UInt8(ascii: "5"), UInt8(ascii: "6"), UInt8(ascii: "7"),
        UInt8(ascii: "8"), UInt8(ascii: "9"), UInt8(ascii: "A"), UInt8(ascii: "B"),
        UInt8(ascii: "C"), UInt8(ascii: "D"), UInt8(ascii: "E"), UInt8(ascii: "F"),
    ]

    /// Use this type to create a backing store for a 8-4-4-4-12 UUID String on stack.
    ///
    /// Using this type we ensure to only have one allocation for creating a String even before Swift 5.3 and it can
    /// also be used as an intermediary before copying the string bytes into a NIO `ByteBuffer`.
    fileprivate typealias uuid_string_t = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    fileprivate static let nullString: uuid_string_t = (
        0, 0, 0, 0, 0, 0, 0, 0, UInt8(ascii: "-"),
        0, 0, 0, 0, UInt8(ascii: "-"),
        0, 0, 0, 0, UInt8(ascii: "-"),
        0, 0, 0, 0, UInt8(ascii: "-"),
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    fileprivate func toAsciiBytesOnStack(characters: [UInt8]) -> uuid_string_t {
        var string: uuid_string_t = Self.nullString
        // to get the best performance we access the lookup table's unsafe buffer pointer
        // since the lookup table has 16 elements and we shift the byte values in such a way
        // that the max value is 15 (last 4 bytes = 16 values). For this reason the lookups
        // are safe and we don't need Swifts safety guards.

        characters.withUnsafeBufferPointer { lookup in
            string.0 = lookup[Int(self.uuid.0 >> 4)]
            string.1 = lookup[Int(self.uuid.0 & 0x0F)]
            string.2 = lookup[Int(self.uuid.1 >> 4)]
            string.3 = lookup[Int(self.uuid.1 & 0x0F)]
            string.4 = lookup[Int(self.uuid.2 >> 4)]
            string.5 = lookup[Int(self.uuid.2 & 0x0F)]
            string.6 = lookup[Int(self.uuid.3 >> 4)]
            string.7 = lookup[Int(self.uuid.3 & 0x0F)]
            string.9 = lookup[Int(self.uuid.4 >> 4)]
            string.10 = lookup[Int(self.uuid.4 & 0x0F)]
            string.11 = lookup[Int(self.uuid.5 >> 4)]
            string.12 = lookup[Int(self.uuid.5 & 0x0F)]
            string.14 = lookup[Int(self.uuid.6 >> 4)]
            string.15 = lookup[Int(self.uuid.6 & 0x0F)]
            string.16 = lookup[Int(self.uuid.7 >> 4)]
            string.17 = lookup[Int(self.uuid.7 & 0x0F)]
            string.19 = lookup[Int(self.uuid.8 >> 4)]
            string.20 = lookup[Int(self.uuid.8 & 0x0F)]
            string.21 = lookup[Int(self.uuid.9 >> 4)]
            string.22 = lookup[Int(self.uuid.9 & 0x0F)]
            string.24 = lookup[Int(self.uuid.10 >> 4)]
            string.25 = lookup[Int(self.uuid.10 & 0x0F)]
            string.26 = lookup[Int(self.uuid.11 >> 4)]
            string.27 = lookup[Int(self.uuid.11 & 0x0F)]
            string.28 = lookup[Int(self.uuid.12 >> 4)]
            string.29 = lookup[Int(self.uuid.12 & 0x0F)]
            string.30 = lookup[Int(self.uuid.13 >> 4)]
            string.31 = lookup[Int(self.uuid.13 & 0x0F)]
            string.32 = lookup[Int(self.uuid.14 >> 4)]
            string.33 = lookup[Int(self.uuid.14 & 0x0F)]
            string.34 = lookup[Int(self.uuid.15 >> 4)]
            string.35 = lookup[Int(self.uuid.15 & 0x0F)]
        }

        return string
    }

    static func fromString(_ string: String) -> LambdaRequestID? {
        guard string.utf8.count == 36 else {
            // invalid length
            return nil
        }
        var string = string
        return string.withUTF8 {
            LambdaRequestID.fromPointer(.init($0))
        }
    }
}

extension LambdaRequestID {
    static func fromPointer(_ ptr: UnsafeRawBufferPointer) -> LambdaRequestID? {
        func uint4Value(from value: UInt8, valid: inout Bool) -> UInt8 {
            switch value {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                return value &- UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                return value &- UInt8(ascii: "a") &+ 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                return value &- UInt8(ascii: "A") &+ 10
            default:
                valid = false
                return 0
            }
        }

        func dashCheck(from value: UInt8, valid: inout Bool) {
            if value != UInt8(ascii: "-") {
                valid = false
            }
        }

        precondition(ptr.count == 36)
        var uuid = Self.null
        var valid = true
        uuid.0 = uint4Value(from: ptr[0], valid: &valid) &<< 4 &+ uint4Value(from: ptr[1], valid: &valid)
        uuid.1 = uint4Value(from: ptr[2], valid: &valid) &<< 4 &+ uint4Value(from: ptr[3], valid: &valid)
        uuid.2 = uint4Value(from: ptr[4], valid: &valid) &<< 4 &+ uint4Value(from: ptr[5], valid: &valid)
        uuid.3 = uint4Value(from: ptr[6], valid: &valid) &<< 4 &+ uint4Value(from: ptr[7], valid: &valid)
        dashCheck(from: ptr[8], valid: &valid)
        uuid.4 = uint4Value(from: ptr[9], valid: &valid) &<< 4 &+ uint4Value(from: ptr[10], valid: &valid)
        uuid.5 = uint4Value(from: ptr[11], valid: &valid) &<< 4 &+ uint4Value(from: ptr[12], valid: &valid)
        dashCheck(from: ptr[13], valid: &valid)
        uuid.6 = uint4Value(from: ptr[14], valid: &valid) &<< 4 &+ uint4Value(from: ptr[15], valid: &valid)
        uuid.7 = uint4Value(from: ptr[16], valid: &valid) &<< 4 &+ uint4Value(from: ptr[17], valid: &valid)
        dashCheck(from: ptr[18], valid: &valid)
        uuid.8 = uint4Value(from: ptr[19], valid: &valid) &<< 4 &+ uint4Value(from: ptr[20], valid: &valid)
        uuid.9 = uint4Value(from: ptr[21], valid: &valid) &<< 4 &+ uint4Value(from: ptr[22], valid: &valid)
        dashCheck(from: ptr[23], valid: &valid)
        uuid.10 = uint4Value(from: ptr[24], valid: &valid) &<< 4 &+ uint4Value(from: ptr[25], valid: &valid)
        uuid.11 = uint4Value(from: ptr[26], valid: &valid) &<< 4 &+ uint4Value(from: ptr[27], valid: &valid)
        uuid.12 = uint4Value(from: ptr[28], valid: &valid) &<< 4 &+ uint4Value(from: ptr[29], valid: &valid)
        uuid.13 = uint4Value(from: ptr[30], valid: &valid) &<< 4 &+ uint4Value(from: ptr[31], valid: &valid)
        uuid.14 = uint4Value(from: ptr[32], valid: &valid) &<< 4 &+ uint4Value(from: ptr[33], valid: &valid)
        uuid.15 = uint4Value(from: ptr[34], valid: &valid) &<< 4 &+ uint4Value(from: ptr[35], valid: &valid)

        if valid {
            return LambdaRequestID(uuid: uuid)
        }

        return nil
    }
}

extension ByteBuffer {
    func getRequestID(at index: Int) -> LambdaRequestID? {
        guard let range = self.rangeWithinReadableBytes(index: index, length: 36) else {
            return nil
        }
        return self.withUnsafeReadableBytes { ptr in
            LambdaRequestID.fromPointer(UnsafeRawBufferPointer(fastRebase: ptr[range]))
        }
    }

    mutating func readRequestID() -> LambdaRequestID? {
        guard let requestID = self.getRequestID(at: self.readerIndex) else {
            return nil
        }
        self.moveReaderIndex(forwardBy: 36)
        return requestID
    }

    @discardableResult
    mutating func setRequestID(_ requestID: LambdaRequestID, at index: Int) -> Int {
        var localBytes = requestID.toAsciiBytesOnStack(characters: LambdaRequestID.lowercaseLookup)
        return withUnsafeBytes(of: &localBytes) {
            self.setBytes($0, at: index)
        }
    }

    mutating func writeRequestID(_ requestID: LambdaRequestID) -> Int {
        let length = self.setRequestID(requestID, at: self.writerIndex)
        self.moveWriterIndex(forwardBy: length)
        return length
    }

    // copy and pasted from NIOCore
    func rangeWithinReadableBytes(index: Int, length: Int) -> Range<Int>? {
        guard index >= self.readerIndex && length >= 0 else {
            return nil
        }

        // both these &-s are safe, they can't underflow because both left & right side are >= 0 (and index >= readerIndex)
        let indexFromReaderIndex = index &- self.readerIndex
        assert(indexFromReaderIndex >= 0)
        guard indexFromReaderIndex <= self.readableBytes &- length else {
            return nil
        }

        let upperBound = indexFromReaderIndex &+ length  // safe, can't overflow, we checked it above.

        // uncheckedBounds is safe because `length` is >= 0, so the lower bound will always be lower/equal to upper
        return Range<Int>(uncheckedBounds: (lower: indexFromReaderIndex, upper: upperBound))
    }
}

// copy and pasted from NIOCore
extension UnsafeRawBufferPointer {
    init(fastRebase slice: Slice<UnsafeRawBufferPointer>) {
        let base = slice.base.baseAddress?.advanced(by: slice.startIndex)
        self.init(start: base, count: slice.endIndex &- slice.startIndex)
    }
}

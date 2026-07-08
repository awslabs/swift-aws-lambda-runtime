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

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if FoundationJSONSupport
public import NIOCore

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

// This is NIO's `NIOFoundationCompat` module which at the moment only adds `ByteBuffer` utility methods
// for Foundation's `Data` type.
//
// The reason that it's not in the `NIO` module is that we don't want to have any direct Foundation dependencies
// in `NIO` as Foundation is problematic for a few reasons:
//
// - its implementation is different on Linux and on macOS which means our macOS tests might be inaccurate
// - on macOS Foundation is mostly written in ObjC which means the autorelease pool might get populated
// - `swift-corelibs-foundation` (the OSS Foundation used on Linux) links the world which will prevent anyone from
//   having static binaries. It can also cause problems in the choice of an SSL library as Foundation already brings
//   the platforms OpenSSL in which might cause problems.

extension ByteBuffer {
    /// Controls how bytes are transferred between `ByteBuffer` and other storage types.
    @usableFromInline
    enum ByteTransferStrategy: Sendable {
        /// Force a copy of the bytes.
        case copy

        /// Do not copy the bytes if at all possible.
        case noCopy

        /// Use a heuristic to decide whether to copy the bytes or not.
        case automatic
    }

    // MARK: - Data APIs

    /// Return `length` bytes starting at `index` and return the result as `Data`. This will not change the reader index.
    /// The selected bytes must be readable or else `nil` will be returned.
    ///
    /// - parameters:
    ///     - index: The starting index of the bytes of interest into the `ByteBuffer`
    ///     - length: The number of bytes of interest
    ///     - byteTransferStrategy: Controls how to transfer the bytes. See `ByteTransferStrategy` for an explanation
    ///                             of the options.
    /// - returns: A `Data` value containing the bytes of interest or `nil` if the selected bytes are not readable.
    @usableFromInline
    func getData(at index0: Int, length: Int, byteTransferStrategy: ByteTransferStrategy) -> Data? {
        let index = index0 - self.readerIndex
        guard index >= 0 && length >= 0 && index <= self.readableBytes - length else {
            return nil
        }
        let doCopy: Bool
        switch byteTransferStrategy {
        case .copy:
            doCopy = true
        case .noCopy:
            doCopy = false
        case .automatic:
            doCopy = length <= 256 * 1024
        }

        return self.withUnsafeReadableBytesWithStorageManagement { ptr, storageRef in
            if doCopy {
                return Data(
                    bytes: UnsafeMutableRawPointer(mutating: ptr.baseAddress!.advanced(by: index)),
                    count: Int(length)
                )
            } else {
                _ = storageRef.retain()
                return Data(
                    bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr.baseAddress!.advanced(by: index)),
                    count: Int(length),
                    deallocator: .custom { _, _ in storageRef.release() }
                )
            }
        }
    }
}
#endif  // trait: FoundationJSONSupport

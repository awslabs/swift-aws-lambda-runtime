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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// extension Array where Element == UInt8 {
//     public var base64: String {
//         Data(self).base64EncodedString()
//     }
// }

extension Data {
    var bytes: [UInt8] {
        [UInt8](self)
    }
}

extension String {
    public var array: [UInt8] {
        Array(self.utf8)
    }
}

extension StringProtocol {
    /// Trims leading and trailing characters matching `predicate`, using only the standard library.
    ///
    /// Replaces Foundation's `trimmingCharacters(in:)` so this stays on FoundationEssentials on Linux.
    func trimming(while predicate: (Character) -> Bool) -> String {
        let withoutLeading = self.drop(while: predicate)
        var end = withoutLeading.endIndex
        while end > withoutLeading.startIndex {
            let previous = withoutLeading.index(before: end)
            guard predicate(withoutLeading[previous]) else { break }
            end = previous
        }
        return String(withoutLeading[withoutLeading.startIndex..<end])
    }
}

extension FileManager {
    // The URL-based `contentsOfDirectory(at:...)`, `enumerator(at:)`, and `URL.resourceValues`
    // live in full Foundation. These helpers rely only on the path-based
    // `contentsOfDirectory(atPath:)`, which FoundationEssentials provides, so directory traversal
    // stays off full Foundation on Linux.

    /// Whether `path` is a directory, determined by attempting to list its contents:
    /// directories succeed (an empty directory returns `[]`), files throw.
    func isDirectory(atPath path: String) -> Bool {
        (try? self.contentsOfDirectory(atPath: path)) != nil
    }

    /// The immediate children of `directory` as URLs, skipping hidden entries.
    func visibleContents(of directory: URL) throws -> [URL] {
        try self.contentsOfDirectory(atPath: directory.path)
            .filter { !$0.hasPrefix(".") }
            .map { directory.appendingPathComponent($0) }
    }
}

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
//  CryptoSwift
//
//  Copyright (C) 2014-2022 Marcin Krzyżanowski <marcin@krzyzanowskim.com>
//  This software is provided 'as-is', without any express or implied warranty.
//
//  In no event will the authors be held liable for any damages arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,including commercial applications, and to alter it and redistribute it freely, subject to the following restrictions:
//
//  - The origin of this software must not be misrepresented; you must not claim that you wrote the original software. If you use this software in a product, an acknowledgment in the product documentation is required.
//  - Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
//  - This notice may not be removed or altered from any source or binary distribution.
//

//  TODO: generic for process32/64 (UInt32/UInt64)
//

public final class SHA2: DigestType {
    @usableFromInline
    let variant: Variant

    @usableFromInline
    let size: Int

    @usableFromInline
    let blockSize: Int

    @usableFromInline
    let digestLength: Int

    private let k: [UInt64]

    @usableFromInline
    var accumulated = [UInt8]()

    @usableFromInline
    var processedBytesTotalCount: Int = 0

    @usableFromInline
    var accumulatedHash32 = [UInt32]()

    @usableFromInline
    var accumulatedHash64 = [UInt64]()

    @frozen
    public enum Variant: RawRepresentable {
        case sha224, sha256, sha384, sha512

        public var digestLength: Int {
            self.rawValue / 8
        }

        public var blockSize: Int {
            switch self {
            case .sha224, .sha256:
                return 64
            case .sha384, .sha512:
                return 128
            }
        }

        public typealias RawValue = Int
        public var rawValue: RawValue {
            switch self {
            case .sha224:
                return 224
            case .sha256:
                return 256
            case .sha384:
                return 384
            case .sha512:
                return 512
            }
        }

        public init?(rawValue: RawValue) {
            switch rawValue {
            case 224:
                self = .sha224
            case 256:
                self = .sha256
            case 384:
                self = .sha384
            case 512:
                self = .sha512
            default:
                return nil
            }
        }

        @usableFromInline
        var h: [UInt64] {
            switch self {
            case .sha224:
                return [
                    0xc105_9ed8, 0x367c_d507, 0x3070_dd17, 0xf70e_5939, 0xffc0_0b31, 0x6858_1511, 0x64f9_8fa7,
                    0xbefa_4fa4,
                ]
            case .sha256:
                return [
                    0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab,
                    0x5be0_cd19,
                ]
            case .sha384:
                return [
                    0xcbbb_9d5d_c105_9ed8, 0x629a_292a_367c_d507, 0x9159_015a_3070_dd17, 0x152f_ecd8_f70e_5939,
                    0x6733_2667_ffc0_0b31, 0x8eb4_4a87_6858_1511, 0xdb0c_2e0d_64f9_8fa7, 0x47b5_481d_befa_4fa4,
                ]
            case .sha512:
                return [
                    0x6a09_e667_f3bc_c908, 0xbb67_ae85_84ca_a73b, 0x3c6e_f372_fe94_f82b, 0xa54f_f53a_5f1d_36f1,
                    0x510e_527f_ade6_82d1, 0x9b05_688c_2b3e_6c1f, 0x1f83_d9ab_fb41_bd6b, 0x5be0_cd19_137e_2179,
                ]
            }
        }

        @usableFromInline
        var finalLength: Int {
            switch self {
            case .sha224:
                return 7
            case .sha384:
                return 6
            default:
                return Int.max
            }
        }
    }

    public init(variant: SHA2.Variant) {
        self.variant = variant
        switch self.variant {
        case .sha224, .sha256:
            self.accumulatedHash32 = variant.h.map { UInt32($0) }  // FIXME: UInt64 for process64
            self.blockSize = variant.blockSize
            self.size = variant.rawValue
            self.digestLength = variant.digestLength
            self.k = [
                0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
                0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
                0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
                0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
                0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
                0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
                0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
                0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
            ]
        case .sha384, .sha512:
            self.accumulatedHash64 = variant.h
            self.blockSize = variant.blockSize
            self.size = variant.rawValue
            self.digestLength = variant.digestLength
            self.k = [
                0x428a_2f98_d728_ae22, 0x7137_4491_23ef_65cd, 0xb5c0_fbcf_ec4d_3b2f, 0xe9b5_dba5_8189_dbbc,
                0x3956_c25b_f348_b538,
                0x59f1_11f1_b605_d019, 0x923f_82a4_af19_4f9b, 0xab1c_5ed5_da6d_8118, 0xd807_aa98_a303_0242,
                0x1283_5b01_4570_6fbe,
                0x2431_85be_4ee4_b28c, 0x550c_7dc3_d5ff_b4e2, 0x72be_5d74_f27b_896f, 0x80de_b1fe_3b16_96b1,
                0x9bdc_06a7_25c7_1235,
                0xc19b_f174_cf69_2694, 0xe49b_69c1_9ef1_4ad2, 0xefbe_4786_384f_25e3, 0x0fc1_9dc6_8b8c_d5b5,
                0x240c_a1cc_77ac_9c65,
                0x2de9_2c6f_592b_0275, 0x4a74_84aa_6ea6_e483, 0x5cb0_a9dc_bd41_fbd4, 0x76f9_88da_8311_53b5,
                0x983e_5152_ee66_dfab,
                0xa831_c66d_2db4_3210, 0xb003_27c8_98fb_213f, 0xbf59_7fc7_beef_0ee4, 0xc6e0_0bf3_3da8_8fc2,
                0xd5a7_9147_930a_a725,
                0x06ca_6351_e003_826f, 0x1429_2967_0a0e_6e70, 0x27b7_0a85_46d2_2ffc, 0x2e1b_2138_5c26_c926,
                0x4d2c_6dfc_5ac4_2aed,
                0x5338_0d13_9d95_b3df, 0x650a_7354_8baf_63de, 0x766a_0abb_3c77_b2a8, 0x81c2_c92e_47ed_aee6,
                0x9272_2c85_1482_353b,
                0xa2bf_e8a1_4cf1_0364, 0xa81a_664b_bc42_3001, 0xc24b_8b70_d0f8_9791, 0xc76c_51a3_0654_be30,
                0xd192_e819_d6ef_5218,
                0xd699_0624_5565_a910, 0xf40e_3585_5771_202a, 0x106a_a070_32bb_d1b8, 0x19a4_c116_b8d2_d0c8,
                0x1e37_6c08_5141_ab53,
                0x2748_774c_df8e_eb99, 0x34b0_bcb5_e19b_48a8, 0x391c_0cb3_c5c9_5a63, 0x4ed8_aa4a_e341_8acb,
                0x5b9c_ca4f_7763_e373,
                0x682e_6ff3_d6b2_b8a3, 0x748f_82ee_5def_b2fc, 0x78a5_636f_4317_2f60, 0x84c8_7814_a1f0_ab72,
                0x8cc7_0208_1a64_39ec,
                0x90be_fffa_2363_1e28, 0xa450_6ceb_de82_bde9, 0xbef9_a3f7_b2c6_7915, 0xc671_78f2_e372_532b,
                0xca27_3ece_ea26_619c,
                0xd186_b8c7_21c0_c207, 0xeada_7dd6_cde0_eb1e, 0xf57d_4f7f_ee6e_d178, 0x06f0_67aa_7217_6fba,
                0x0a63_7dc5_a2c8_98a6,
                0x113f_9804_bef9_0dae, 0x1b71_0b35_131c_471b, 0x28db_77f5_2304_7d84, 0x32ca_ab7b_40c7_2493,
                0x3c9e_be0a_15c9_bebc,
                0x431d_67c4_9c10_0d4c, 0x4cc5_d4be_cb3e_42b6, 0x597f_299c_fc65_7e2a, 0x5fcb_6fab_3ad6_faec,
                0x6c44_198c_4a47_5817,
            ]
        }
    }

    @inlinable
    public func calculate(for bytes: [UInt8]) -> [UInt8] {
        do {
            return try update(withBytes: bytes.slice, isLast: true)
        } catch {
            return []
        }
    }

    public func callAsFunction(_ bytes: [UInt8]) -> [UInt8] {
        calculate(for: bytes)
    }

    @usableFromInline
    func process64(block chunk: ArraySlice<UInt8>, currentHash hh: inout [UInt64]) {
        // break chunk into sixteen 64-bit words M[j], 0 ≤ j ≤ 15, big-endian
        // Extend the sixteen 64-bit words into eighty 64-bit words:
        let M = UnsafeMutablePointer<UInt64>.allocate(capacity: self.k.count)
        M.initialize(repeating: 0, count: self.k.count)
        defer {
            M.deinitialize(count: self.k.count)
            M.deallocate()
        }
        for x in 0..<self.k.count {
            switch x {
            case 0...15:
                let start = chunk.startIndex.advanced(by: x * 8)  // * MemoryLayout<UInt64>.size
                M[x] = UInt64(bytes: chunk, fromIndex: start)
            default:
                let s0 = rotateRight(M[x - 15], by: 1) ^ rotateRight(M[x - 15], by: 8) ^ (M[x - 15] >> 7)
                let s1 = rotateRight(M[x - 2], by: 19) ^ rotateRight(M[x - 2], by: 61) ^ (M[x - 2] >> 6)
                M[x] = M[x - 16] &+ s0 &+ M[x - 7] &+ s1
            }
        }

        var A = hh[0]
        var B = hh[1]
        var C = hh[2]
        var D = hh[3]
        var E = hh[4]
        var F = hh[5]
        var G = hh[6]
        var H = hh[7]

        // Main loop
        for j in 0..<self.k.count {
            let s0 = rotateRight(A, by: 28) ^ rotateRight(A, by: 34) ^ rotateRight(A, by: 39)
            let maj = (A & B) ^ (A & C) ^ (B & C)
            let t2 = s0 &+ maj
            let s1 = rotateRight(E, by: 14) ^ rotateRight(E, by: 18) ^ rotateRight(E, by: 41)
            let ch = (E & F) ^ ((~E) & G)
            let t1 = H &+ s1 &+ ch &+ self.k[j] &+ UInt64(M[j])

            H = G
            G = F
            F = E
            E = D &+ t1
            D = C
            C = B
            B = A
            A = t1 &+ t2
        }

        hh[0] = (hh[0] &+ A)
        hh[1] = (hh[1] &+ B)
        hh[2] = (hh[2] &+ C)
        hh[3] = (hh[3] &+ D)
        hh[4] = (hh[4] &+ E)
        hh[5] = (hh[5] &+ F)
        hh[6] = (hh[6] &+ G)
        hh[7] = (hh[7] &+ H)
    }

    // mutating currentHash in place is way faster than returning new result
    @usableFromInline
    func process32(block chunk: ArraySlice<UInt8>, currentHash hh: inout [UInt32]) {
        // break chunk into sixteen 32-bit words M[j], 0 ≤ j ≤ 15, big-endian
        // Extend the sixteen 32-bit words into sixty-four 32-bit words:
        let M = UnsafeMutablePointer<UInt32>.allocate(capacity: self.k.count)
        M.initialize(repeating: 0, count: self.k.count)
        defer {
            M.deinitialize(count: self.k.count)
            M.deallocate()
        }

        for x in 0..<self.k.count {
            switch x {
            case 0...15:
                let start = chunk.startIndex.advanced(by: x * 4)  // * MemoryLayout<UInt32>.size
                M[x] = UInt32(bytes: chunk, fromIndex: start)
            default:
                let s0 = rotateRight(M[x - 15], by: 7) ^ rotateRight(M[x - 15], by: 18) ^ (M[x - 15] >> 3)
                let s1 = rotateRight(M[x - 2], by: 17) ^ rotateRight(M[x - 2], by: 19) ^ (M[x - 2] >> 10)
                M[x] = M[x - 16] &+ s0 &+ M[x - 7] &+ s1
            }
        }

        var A = hh[0]
        var B = hh[1]
        var C = hh[2]
        var D = hh[3]
        var E = hh[4]
        var F = hh[5]
        var G = hh[6]
        var H = hh[7]

        // Main loop
        for j in 0..<self.k.count {
            let s0 = rotateRight(A, by: 2) ^ rotateRight(A, by: 13) ^ rotateRight(A, by: 22)
            let maj = (A & B) ^ (A & C) ^ (B & C)
            let t2 = s0 &+ maj
            let s1 = rotateRight(E, by: 6) ^ rotateRight(E, by: 11) ^ rotateRight(E, by: 25)
            let ch = (E & F) ^ ((~E) & G)
            let t1 = H &+ s1 &+ ch &+ UInt32(self.k[j]) &+ M[j]

            H = G
            G = F
            F = E
            E = D &+ t1
            D = C
            C = B
            B = A
            A = t1 &+ t2
        }

        hh[0] = hh[0] &+ A
        hh[1] = hh[1] &+ B
        hh[2] = hh[2] &+ C
        hh[3] = hh[3] &+ D
        hh[4] = hh[4] &+ E
        hh[5] = hh[5] &+ F
        hh[6] = hh[6] &+ G
        hh[7] = hh[7] &+ H
    }
}

extension SHA2: Updatable {

    @inlinable
    public func update(withBytes bytes: ArraySlice<UInt8>, isLast: Bool = false) throws -> [UInt8] {
        self.accumulated += bytes

        if isLast {
            let lengthInBits = (processedBytesTotalCount + self.accumulated.count) * 8
            let lengthBytes = lengthInBits.bytes(totalBytes: self.blockSize / 8)
            // A 64-bit/128-bit representation of b. blockSize fit by accident.

            // Step 1. Append padding
            bitPadding(to: &self.accumulated, blockSize: self.blockSize, allowance: self.blockSize / 8)

            // Step 2. Append Length a 64-bit representation of lengthInBits
            self.accumulated += lengthBytes
        }

        var processedBytes = 0
        for chunk in self.accumulated.batched(by: self.blockSize) {
            if isLast || (self.accumulated.count - processedBytes) >= self.blockSize {
                switch self.variant {
                case .sha224, .sha256:
                    self.process32(block: chunk, currentHash: &self.accumulatedHash32)
                case .sha384, .sha512:
                    self.process64(block: chunk, currentHash: &self.accumulatedHash64)
                }
                processedBytes += chunk.count
            }
        }
        self.accumulated.removeFirst(processedBytes)
        self.processedBytesTotalCount += processedBytes

        // output current hash
        var result = [UInt8](repeating: 0, count: variant.digestLength)
        switch self.variant {
        case .sha224, .sha256:
            var pos = 0
            for idx in 0..<self.accumulatedHash32.count where idx < self.variant.finalLength {
                let h = accumulatedHash32[idx]
                result[pos + 0] = UInt8((h >> 24) & 0xff)
                result[pos + 1] = UInt8((h >> 16) & 0xff)
                result[pos + 2] = UInt8((h >> 8) & 0xff)
                result[pos + 3] = UInt8(h & 0xff)
                pos += 4
            }
        case .sha384, .sha512:
            var pos = 0
            for idx in 0..<self.accumulatedHash64.count where idx < self.variant.finalLength {
                let h = accumulatedHash64[idx]
                result[pos + 0] = UInt8((h >> 56) & 0xff)
                result[pos + 1] = UInt8((h >> 48) & 0xff)
                result[pos + 2] = UInt8((h >> 40) & 0xff)
                result[pos + 3] = UInt8((h >> 32) & 0xff)
                result[pos + 4] = UInt8((h >> 24) & 0xff)
                result[pos + 5] = UInt8((h >> 16) & 0xff)
                result[pos + 6] = UInt8((h >> 8) & 0xff)
                result[pos + 7] = UInt8(h & 0xff)
                pos += 8
            }
        }

        // reset hash value for instance
        if isLast {
            switch self.variant {
            case .sha224, .sha256:
                // FIXME: UInt64 for process64
                self.accumulatedHash32 = self.variant.h.lazy.map { UInt32($0) }
            case .sha384, .sha512:
                self.accumulatedHash64 = self.variant.h
            }
        }

        return result
    }
}

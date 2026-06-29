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

// `stdout` is a libc global `var` (an `extern FILE *`) and so reading it trips the Swift 6
// strict-concurrency check. `@preconcurrency` silences that diagnostic for libc symbols. It is
// confined to this dedicated file — the rest of the target imports libc normally and keeps full
// concurrency checking — to keep the suppression's blast radius as small as possible.
#if os(macOS)
@preconcurrency import Darwin.C
#elseif canImport(Glibc)
@preconcurrency import Glibc
#elseif canImport(Musl)
@preconcurrency import Musl
#elseif os(Windows)
@preconcurrency import ucrt
#else
#error("Unsupported platform")
#endif

/// Switches `stdout` to line buffering.
///
/// SwiftPM runs plugins with stdout connected to a pipe rather than a TTY, so the C runtime
/// block-buffers stdout and the helper's output (and `--help` text) only appears once the process
/// exits. Line buffering makes each printed line stream to the user as it is produced.
///
/// Must be called once, before any output is produced.
func enableLineBufferedStdout() {
    setvbuf(stdout, nil, _IOLBF, 0)
}

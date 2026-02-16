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

import Dispatch
import Foundation
import PackagePlugin
import Synchronization

@available(macOS 15.0, *)
struct Utils {
    @discardableResult
    static func execute(
        executable: URL,
        arguments: [String],
        customWorkingDirectory: URL? = .none,
        logLevel: ProcessLogLevel
    ) throws -> String {
        if logLevel >= .debug {
            print("\(executable.path()) \(arguments.joined(separator: " "))")
            if let customWorkingDirectory {
                print("Working directory: \(customWorkingDirectory.path())")
            }
        }

        let fd = dup(1)
        let stdout = fdopen(fd, "rw")
        defer { if let so = stdout { fclose(so) } }

        // We need to use an unsafe transfer here to get the fd into our Sendable closure.
        // This transfer is fine, because we write to the variable from a single SerialDispatchQueue here.
        // We wait until the process is run below process.waitUntilExit().
        // This means no further writes to output will happen.
        // This makes it save for us to read the output
        struct UnsafeTransfer<Value>: @unchecked Sendable {
            let value: Value
        }

        let outputMutex = Mutex("")
        let outputSync = DispatchGroup()
        let outputQueue = DispatchQueue(label: "AWSLambdaPackager.output")
        let unsafeTransfer = UnsafeTransfer(value: stdout)
        let outputHandler = { @Sendable (data: Data?) in
            dispatchPrecondition(condition: .onQueue(outputQueue))

            outputSync.enter()
            defer { outputSync.leave() }

            guard
                let _output = data.flatMap({
                    String(data: $0, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(["\n"]))
                }), !_output.isEmpty
            else {
                return
            }

            outputMutex.withLock { output in
                output += _output + "\n"
            }

            switch logLevel {
            case .silent:
                break
            case .debug(let outputIndent), .output(let outputIndent):
                print(String(repeating: " ", count: outputIndent), terminator: "")
                print(_output)
                fflush(unsafeTransfer.value)
            }
        }

        let pipe = Pipe()

        let process = Process()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = executable
        process.arguments = arguments
        if let customWorkingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: customWorkingDirectory.path())
        }

        // Read from the pipe on a background thread using a manual read loop.
        // We avoid FileHandle.readabilityHandler because on Linux its setter
        // triggers _bridgeAnythingToObjectiveC / swift_dynamicCast which can
        // crash with a SIGSEGV during concurrent Swift runtime metadata resolution.
        let readFileHandle = pipe.fileHandleForReading
        outputSync.enter()
        outputQueue.async {
            defer { outputSync.leave() }
            // Read in a loop until EOF
            while true {
                let data = readFileHandle.availableData
                if data.isEmpty {
                    break  // EOF
                }
                outputHandler(data)
            }
        }

        try process.run()
        process.waitUntilExit()

        // wait for output to be fully processed
        outputSync.wait()

        let output = outputMutex.withLock { $0 }

        if process.terminationStatus != 0 {
            // print output on failure and if not already printed
            if logLevel < .output {
                print(output)
                fflush(stdout)
            }
            throw ProcessError.processFailed([executable.path()] + arguments, process.terminationStatus)
        }

        return output
    }

    enum ProcessError: Error, CustomStringConvertible {
        case processFailed([String], Int32)

        var description: String {
            switch self {
            case .processFailed(let arguments, let code):
                return "\(arguments.joined(separator: " ")) failed with code \(code)"
            }
        }
    }

    enum ProcessLogLevel: Comparable {
        case silent
        case output(outputIndent: Int)
        case debug(outputIndent: Int)

        var naturalOrder: Int {
            switch self {
            case .silent:
                return 0
            case .output:
                return 1
            case .debug:
                return 2
            }
        }

        static var output: Self {
            .output(outputIndent: 2)
        }

        static var debug: Self {
            .debug(outputIndent: 2)
        }

        static func < (lhs: ProcessLogLevel, rhs: ProcessLogLevel) -> Bool {
            lhs.naturalOrder < rhs.naturalOrder
        }
    }
}

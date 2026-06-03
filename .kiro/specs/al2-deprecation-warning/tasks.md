# Implementation Plan

- [x] 1. Revert default base Docker image to amazonlinux2
  - In `Plugins/AWSLambdaPackager/Plugin.swift`, in the `Configuration` struct `init`, remove the `amazonLinuxVersion` variable and all version-parsing logic (the `if let version = swiftVersion { ... }` block)
  - Replace the `baseDockerImage` assignment with the pre-7615923 single-line (`self.baseDockerImage = baseDockerImageArgument.first ?? "swift:\(swiftVersion.map { $0 + "-" } ?? "")amazonlinux2"`)
  - Remove the verbose logging block that prints swift version/amazon linux version/base docker image info
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 2. Refine platform detection methods
  - In `Plugins/AWSLambdaPackager/Plugin.swift`, replace the `isAmazonLinux()` method with `isAmazonLinux2()` (returns true if `/etc/system-release` starts with "Amazon Linux release 2" but NOT "Amazon Linux release 2023")
  - Add `isAmazonLinux2023()` method (returns true if starts with "Amazon Linux release 2023")
  - Update all call sites to use the new methods
  - _Requirements: 3.1, 4.2_

- [x] 3. Add deprecation warning method
  - Add a `private func displayDeprecationWarning()` method that prints the multi-line warning with EOL notice, migration instruction, `--base-docker-image swift:6.3-amazonlinux2023` option, `provided.al2023` runtime reminder, and `https://aws.amazon.com/amazon-linux-2` URL, surrounded by separator lines
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 3.2, 3.3, 3.4, 3.5_

- [x] 4. Update build flow in performCommand
  - Replace the `if self.isAmazonLinux()` block with three-way branching — `isAmazonLinux2()` prints warning then proceeds with native build, `isAmazonLinux2023()` does native build without warning, else does Docker build with warning if image contains "amazonlinux2" but not "amazonlinux2023"
  - Warning is printed exactly once before the first product build
  - No errors are thrown — the build always continues
  - _Requirements: 2.1, 2.8, 2.9, 3.1, 3.2, 4.1, 4.2, 4.3_

- [x] 5. Update help message
  - In `displayHelpMessage()`, update the `--base-docker-image` description to show `(default: swift:<version>-amazonlinux2)` and add a note that Amazon Linux 2023 will become the default after June 30, 2025
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 6. Update quick-setup documentation
  - In `Sources/AWSLambdaRuntime/Docs.docc/quick-setup.md`, ensure archive example shows `swift:amazonlinux2`, add a note explaining AL2 is EOL and developers should migrate using `--base-docker-image swift:6.3-amazonlinux2023`, and mention that AL2023 deployments must use `provided.al2023` runtime
  - _Requirements: 6.1, 6.2_

- [x] 7. Update readme documentation
  - In `readme.md`, ensure deployment examples reference `provided.al2`, add a note about `--base-docker-image swift:6.3-amazonlinux2023` for early migration, and mention that AL2023 deployments must use `provided.al2023` runtime
  - _Requirements: 6.3, 6.4_

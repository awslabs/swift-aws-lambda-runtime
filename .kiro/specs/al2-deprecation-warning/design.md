# Design Document

## Overview

This design describes the changes to the `AWSLambdaPackager` plugin to revert the default Docker base image to Amazon Linux 2 and introduce a prominent deprecation warning when AL2 is used. The warning informs developers about the EOL status and guides them to migrate to AL2023.

The changes are confined to a single file (`Plugins/AWSLambdaPackager/Plugin.swift`) plus documentation updates. No new modules or dependencies are introduced.

## Architecture

### Flow Diagram

```
performCommand()
    │
    ├── Parse configuration (baseDockerImage defaults to amazonlinux2)
    │
    ├── if isAmazonLinux2() (native on AL2)
    │   ├── print deprecation warning
    │   └── proceed with native build
    │
    ├── if isAmazonLinux2023() (native on AL2023)
    │   └── proceed with native build (no warning)
    │
    └── else (not on Amazon Linux → Docker build)
        ├── if baseDockerImage contains "amazonlinux2" but NOT "amazonlinux2023"
        │   └── print deprecation warning
        └── proceed with Docker build
```

## Components and Interfaces

### Modified Components

| Component | File | Change |
|-----------|------|--------|
| `Configuration` struct | `Plugin.swift` | Revert `baseDockerImage` to always use `amazonlinux2` |
| `AWSLambdaPackager.performCommand()` | `Plugin.swift` | Add deprecation warning logic before build |
| `AWSLambdaPackager.isAmazonLinux()` | `Plugin.swift` | Split into `isAmazonLinux2()` and `isAmazonLinux2023()` |
| `AWSLambdaPackager.displayHelpMessage()` | `Plugin.swift` | Update default image text and add migration note |
| Quick-setup docs | `quick-setup.md` | Add migration note |
| Readme | `readme.md` | Add migration note |

### New Methods

```swift
/// Prints a prominent deprecation warning about Amazon Linux 2 EOL.
private func displayDeprecationWarning()

/// Returns true if running natively on Amazon Linux 2 (not AL2023).
private func isAmazonLinux2() -> Bool

/// Returns true if running natively on Amazon Linux 2023.
private func isAmazonLinux2023() -> Bool
```

### Interfaces

No public API changes. All modifications are internal to the plugin.

## Testing Strategy

Since this is a SwiftPM plugin, automated unit testing is limited. Verification approach:

1. **macOS Docker build (AL2 default)** — Run `swift package --allow-network-connections docker archive` and verify the deprecation warning appears, then the build completes
2. **macOS Docker build (AL2023 explicit)** — Run with `--base-docker-image swift:6.3-amazonlinux2023` and verify no warning appears
3. **Native on AL2** — Run inside an AL2 container and verify the warning appears, then the build completes
4. **Native on AL2023** — Run inside an AL2023 container and verify native build proceeds without warning
5. **Help message** — Run with `--help` and verify the updated text

## Data Models

### Configuration Change

The `baseDockerImage` property computation reverts to the pre-7615923 logic:

```swift
// Before (commit 7615923): version-based AL2/AL2023 selection
// After (this change): always amazonlinux2
self.baseDockerImage =
    baseDockerImageArgument.first ?? "swift:\(swiftVersion.map { $0 + "-" } ?? "")amazonlinux2"
```

No new data models or stored state are introduced.

## Error Handling

### Native Build on AL2

When the plugin detects it is running natively on Amazon Linux 2, it prints the deprecation warning and proceeds with the native build. No error is thrown — this is a non-blocking warning.

### Docker Build with AL2 Image

When building via Docker with an AL2 image, the warning is printed and the build continues normally. No error is thrown — this is a non-blocking warning.

### AL2023 (Native or Docker)

No warning, no error. Build proceeds as normal.

## Correctness Properties

### Property 1: Warning Uniqueness
When multiple products are built in a single invocation, the deprecation warning is printed exactly once before the first build starts, not repeated per product.
**Validates: Requirements 2.9**

### Property 2: AL2 vs AL2023 Detection
The string matching uses `hasPrefix("Amazon Linux release 2")` with a negative check for `hasPrefix("Amazon Linux release 2023")` to correctly distinguish AL2 from AL2023.
**Validates: Requirements 3.1**

### Property 3: Docker Image String Matching
Uses `contains("amazonlinux2")` with negative `contains("amazonlinux2023")` to handle various image name formats (e.g., `swift:6.3-amazonlinux2`, `swift:amazonlinux2`).
**Validates: Requirements 2.1**

### Property 4: Backward Compatibility
The `--base-docker-image` flag still allows developers to specify any image, bypassing the default entirely.
**Validates: Requirements 1.3**

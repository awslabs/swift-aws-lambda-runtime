# Implementation Plan

- [x] 1. Create the extension file and basic structure
  - Create `Sources/AWSLambdaRuntime/LambdaResponseStreamWriter+Headers.swift` file
  - Add appropriate imports for FoundationEssentials/Foundation and NIOCore
  - Add file header with copyright and license information matching existing files
  - _Requirements: 1.3, 3.4_

- [x] 2. Implement StreamingLambdaStatusAndHeadersResponse structure
  - Define the `StreamingLambdaStatusAndHeadersResponse` struct with `Codable` and `Sendable` conformance
  - Add `statusCode`, `headers`, and `multiValueHeaders` properties with correct types
  - Implement public initializer with default values for optional parameters
  - _Requirements: 3.1, 3.2, 3.3_

- [x] 3. Implement the writeStatusAndHeaders method
  - Add `writeStatusAndHeaders(_:)` method to `LambdaResponseStreamWriter` extension
  - Implement JSON serialization using `JSONEncoder`
  - Write serialized JSON data using existing `write(_:)` method
  - Write eight null bytes (0x00) as separator after JSON data
  - Mark method as `async throws` for proper error handling
  - _Requirements: 1.1, 1.4, 4.1, 4.2, 4.3, 6.1, 6.2, 6.4_

- [x] 4. Create unit tests for the new functionality
  - Create test file `Tests/AWSLambdaRuntimeTests/LambdaResponseStreamWriter+HeadersTests.swift`
  - Implement mock `LambdaResponseStreamWriter` for testing
  - Write tests for successful header writing with minimal response (status code only)
  - Write tests for successful header writing with full response (all fields populated)
  - Verify JSON serialization format matches expected structure
  - Verify null byte separator is written correctly after JSON data
  - _Requirements: 1.1, 1.4, 4.1, 4.2, 4.3_

- [x] 5. Add error handling tests
  - Write tests for JSON serialization error propagation
  - Write tests for write method error propagation
  - Verify error types and messages are properly handled
  - _Requirements: 6.1, 6.2, 6.3_

- [x] 6. Add integration tests
  - Test writeStatusAndHeaders method with existing streaming methods
  - Test multiple header writes to ensure they work correctly
  - Test header write followed by body streaming to verify compatibility
  - Verify the method works with all existing `LambdaResponseStreamWriter` implementations
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [ ] 7. Update Examples/Streaming example
  - Update `Examples/Streaming/Sources/main.swift` to demonstrate the new writeStatusAndHeaders functionality
  - Add example usage showing how to set status code and headers before streaming response body
  - Update `Examples/Streaming/README.md` to document the new header functionality
  - Include code examples and explanation of the streaming response format
  - _Requirements: 1.1, 1.2_

- [x] 8. Update top-level README documentation
  - Update the streaming section in the main `readme.md` file
  - Add documentation about the new writeStatusAndHeaders method
  - Include example code showing how to use the new functionality
  - Focus on user-facing API and benefits without exposing implementation details
  - _Requirements: 1.1, 1.2_
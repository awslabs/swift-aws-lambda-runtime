# Design Document

## Overview

This design implements HTTP header and status code support for the `LambdaResponseStreamWriter` protocol through a protocol extension. The solution creates a new response structure specifically for streaming scenarios and adds a method to send HTTP response metadata before streaming the body content. The implementation ensures proper separation between metadata and streaming data using a null byte delimiter.

## Architecture

The feature consists of two main components:

1. **StreamingLambdaResponse Structure**: A new `Codable` and `Sendable` struct that represents HTTP response metadata without body content
2. **LambdaResponseStreamWriter Extension**: A protocol extension that adds the `writeHeaders(_:)` method to send response metadata

The architecture maintains compatibility with existing streaming functionality while adding the capability to send structured HTTP response metadata before streaming begins.

## Components and Interfaces

### StreamingLambdaResponse Structure

```swift
public struct StreamingLambdaStatusAndHeadersResponse: Codable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]?
    
    public init(
        statusCode: Int,
        headers: [String: String]? = nil,
    )
}
```

**Design Decisions:**
- All properties are public to allow full control over response metadata
- there is no `body` property
- Default values provided for optional parameters to simplify common use cases
- Follows standard AWS Lambda response format for consistency

### LambdaResponseStreamWriter Extension

```swift
extension LambdaResponseStreamWriter {
    public func writeStatusAndHeaders(_ response: StreamingLambdaStatusAndHeadersResponse) async throws
}
```

**Method Behavior:**
1. Validates that `response.body` is nil, throwing an error if not
2. Serializes the response structure to JSON using `JSONEncoder`
3. Writes the JSON data to the stream using existing `write(_:)` method
4. Writes eight null bytes (0x00) as a separator
5. Propagates any errors from validation, serialization, or writing

## Data Models

### StreamingLambdaStatusAndHeadersResponse Properties

- **statusCode**: HTTP status code (e.g., 200, 404, 500)
- **headers**: Dictionary of single-value HTTP headers
- **multiValueHeaders**: Dictionary of multi-value HTTP headers (e.g., Set-Cookie)

### JSON Serialization Format

The serialized JSON follows this structure:
```json
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json",
        "Cache-Control": "no-cache"
    },
    "multiValueHeaders": {
        "Set-Cookie": ["session=abc123", "theme=dark"]
    }
}
```

## Error Handling

### Serialization Errors

- **JSON Encoding Errors**: Propagated from `JSONEncoder.encode(_:)`
- **Write Errors**: Propagated from underlying `write(_:)` method calls

### Error Propagation Strategy

All errors are propagated to the caller without modification, maintaining consistency with existing protocol behavior. The method signature `async throws` ensures proper error handling integration.

## Testing Strategy

### Unit Tests

1. **Successful Header Writing**
   - Test with minimal response (status code only)
   - Test with full response (all optional fields populated)
   - Verify JSON serialization format
   - Verify null byte separator is written

2. **Validation Tests**
   - Test error message content and type

3. **Error Handling Tests**
   - Test JSON serialization error propagation
   - Test write method error propagation

4. **Integration Tests**
   - Test with existing streaming methods
   - Test multiple header writes (should work)
   - Test header write followed by body streaming

### Mock Implementation

Tests will use a mock `LambdaResponseStreamWriter` implementation that captures written data for verification:

```swift
class MockLambdaResponseStreamWriter: LambdaResponseStreamWriter {
    var writtenBuffers: [ByteBuffer] = []
    
    func write(_ buffer: ByteBuffer) async throws {
        writtenBuffers.append(buffer)
    }
    
    func finish() async throws {}
    func writeAndFinish(_ buffer: ByteBuffer) async throws {}
}
```

## Implementation Notes

### File Organization

- **File Location**: `Sources/AWSLambdaRuntime/LambdaResponseStreamWriter+Headers.swift`
- **Imports**: FoundationEssentials if it can be imported, Foundation otherwise (for JSONEncoder), NIOCore (for ByteBuffer)
- **Structure**: Response struct definition followed by protocol extension

### Performance Considerations

- JSON serialization is performed once per header write
- Null byte separator uses minimal memory (8 bytes)
- No additional memory allocations beyond JSON encoding

### Compatibility

- Maintains full backward compatibility with existing `LambdaResponseStreamWriter` implementations
- Does not modify existing protocol methods
- Can be used alongside existing streaming methods without conflicts
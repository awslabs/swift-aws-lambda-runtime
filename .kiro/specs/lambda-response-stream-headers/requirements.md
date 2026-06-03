# Requirements Document

## Introduction

This feature adds HTTP header and status code support to the `LambdaResponseStreamWriter` protocol by creating an extension that allows sending HTTP response metadata before streaming the response body. This enhancement includes creating a new response structure specifically for streaming scenarios and enables Lambda functions using streaming responses to properly set HTTP status codes, headers, and multi-value headers before writing the response stream.

## Requirements

### Requirement 1

**User Story:** As a Lambda function developer using streaming responses, I want to send HTTP headers and status code before streaming the response body, so that I can properly control the HTTP response metadata.

#### Acceptance Criteria

1. WHEN a developer calls the new method on `LambdaResponseStreamWriter` THEN the system SHALL create a new response structure and serialize it to write to the stream
2. WHEN the method is called THEN the system SHALL accept parameters for status code, headers, multi-value headers, and base64 encoding flag
3. WHEN the method is called THEN the system SHALL be implemented as an extension in a separate file named `LambdaResponseStreamWriter+Headers.swift`
4. WHEN the method is called THEN the system SHALL use the existing `write(_:)` method to send the serialized response

### Requirement 2

**User Story:** As a Lambda function developer, I want the new header method to integrate seamlessly with existing streaming functionality, so that I can use it alongside current streaming methods.

#### Acceptance Criteria

1. WHEN the new method is implemented THEN it SHALL be part of an extension to the existing `LambdaResponseStreamWriter` protocol
2. WHEN the method is called THEN it SHALL not interfere with existing `write(_:)`, `finish()`, and `writeAndFinish(_:)` methods
3. WHEN the method is called THEN it SHALL follow the same async/throws pattern as existing protocol methods
4. WHEN the method is called THEN it SHALL maintain compatibility with all existing `LambdaResponseStreamWriter` implementations

### Requirement 3

**User Story:** As a Lambda function developer, I want a new response structure specifically designed for streaming scenarios, so that I can properly format HTTP response metadata without including body content.

#### Acceptance Criteria

1. WHEN the new response structure is created THEN it SHALL include properties for `isBase64Encoded`, `statusCode`, `headers`, `multiValueHeaders`, and `body`
2. WHEN the structure is defined THEN it SHALL follow the JSON format: `{"isBase64Encoded": true|false, "statusCode": httpStatusCode, "headers": {"headerName": "headerValue"}, "multiValueHeaders": {"headerName": ["headerValue1", "headerValue2"]}, "body": "..."}`
3. WHEN the structure is created THEN it SHALL be `Codable` and `Sendable` to support JSON serialization and concurrency
4. WHEN the structure is used THEN it SHALL be defined in the same file as the extension for organizational purposes

### Requirement 4

**User Story:** As a Lambda function developer, I want the header response to be properly separated from the streaming data, so that the Lambda runtime can distinguish between metadata and body content.

#### Acceptance Criteria

1. WHEN the response structure is serialized and written THEN the system SHALL write a series of eight 0x00 characters immediately after to separate header content from user stream data
2. WHEN the separator is written THEN it SHALL serve as a delimiter between the JSON header response and the subsequent streaming body data
3. WHEN the method is called THEN the system SHALL ensure the separator is always written after the serialized response
4. WHEN streaming continues THEN user data written after the separator SHALL be treated as the response body

### Requirement 5

**User Story:** As a Lambda function developer, I want to ensure the response structure is correct for streaming, so that the body content is only sent through the stream and not duplicated in the JSON response.

#### Acceptance Criteria

1. WHEN the response structure parameter is provided THEN the system SHALL validate that the `body` property is nil
2. WHEN the `body` property is not nil THEN the system SHALL throw an error indicating that body content must be streamed separately
3. WHEN validation passes THEN the system SHALL proceed with serialization of the response object
4. WHEN the error is thrown THEN it SHALL provide a clear message explaining that body content should be sent via streaming methods

### Requirement 6

**User Story:** As a Lambda function developer, I want proper error handling when sending headers, so that serialization failures are properly communicated.

#### Acceptance Criteria

1. WHEN the response structure serialization fails THEN the system SHALL throw an appropriate error
2. WHEN the underlying `write(_:)` method fails THEN the system SHALL propagate the error to the caller
3. WHEN an error occurs THEN the system SHALL maintain the same error handling behavior as existing protocol methods
4. WHEN the method is called THEN it SHALL be marked as `async throws` to match the protocol's error handling pattern
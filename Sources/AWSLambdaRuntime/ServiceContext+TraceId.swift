import ServiceContextModule

// MARK: - ServiceContext integration

/// A ``ServiceContextKey`` for the AWS X-Ray trace ID.
///
/// This allows downstream libraries that depend on `swift-service-context`
/// (but not on `AWSLambdaRuntime`) to access the current trace ID via
/// `ServiceContext.current?.traceID`.
private enum LambdaTraceIDKey: ServiceContextKey {
    typealias Value = String
    static var nameOverride: String? { AmazonHeaders.traceID }
}

extension ServiceContext {
    /// The AWS X-Ray trace ID for the current Lambda invocation, if available.
    ///
    /// This value is automatically set by the Lambda runtime before calling the handler
    /// and is available to all code running within the handler's async task tree.
    ///
    /// Downstream libraries can read this without depending on `AWSLambdaRuntime`:
    /// ```swift
    /// if let traceID = ServiceContext.current?.traceID {
    ///     // propagate traceID to outgoing HTTP requests, etc.
    /// }
    /// ```
    public var traceID: String? {
        get {
            self[LambdaTraceIDKey.self]
        }
        set {
            self[LambdaTraceIDKey.self] = newValue
        }
    }
}
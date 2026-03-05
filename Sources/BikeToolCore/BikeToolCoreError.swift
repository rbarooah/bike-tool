import Foundation

/// Core-library error wrapper for Bike document parsing, mutation, and persistence failures.
public struct BikeToolCoreError: Error, CustomStringConvertible {
    /// Human-readable description suitable for CLI output or agent/user messages.
    public let message: String

    /// Creates a core error with a user-facing message.
    /// - Parameter message: Error text describing the failure.
    public init(message: String) {
        self.message = message
    }

    /// Returns the wrapped message.
    public var description: String { message }
}

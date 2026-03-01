import Foundation

public struct BikeToolCoreError: Error, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

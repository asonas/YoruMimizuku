import Foundation

/// Errors from the account persistence layer.
public enum AccountError: Error, Equatable {
    case unknownAccount(String)
    case noCurrentAccount
}

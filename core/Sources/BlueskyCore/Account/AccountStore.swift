import Foundation

/// Persists accounts and the accounts index to a `SecureStorage`. Keys:
/// "account.<did>" for each account, "accounts.index" for the index. Pure logic;
/// all crypto/OS concerns live behind `SecureStorage`.
public struct AccountStore: Sendable {
    private let storage: SecureStorage
    private let indexKey = "accounts.index"

    public init(storage: SecureStorage) {
        self.storage = storage
    }

    private func accountKey(_ did: String) -> String { "account.\(did)" }

    public func index() throws -> AccountsIndex {
        guard let data = try storage.data(for: indexKey) else { return AccountsIndex() }
        return try JSONDecoder().decode(AccountsIndex.self, from: data)
    }

    private func writeIndex(_ index: AccountsIndex) throws {
        try storage.set(try JSONEncoder().encode(index), for: indexKey)
    }

    public func account(did: String) throws -> PersistedAccount? {
        guard let data = try storage.data(for: accountKey(did)) else { return nil }
        return try JSONDecoder().decode(PersistedAccount.self, from: data)
    }

    /// Save the account and add its DID to the index (no duplicates).
    public func save(_ account: PersistedAccount) throws {
        try storage.set(try JSONEncoder().encode(account), for: accountKey(account.did))
        var idx = try index()
        if !idx.dids.contains(account.did) {
            idx.dids.append(account.did)
            try writeIndex(idx)
        }
    }

    /// Set the current account. Throws `unknownAccount` if the DID is not indexed.
    public func setCurrent(did: String) throws {
        var idx = try index()
        guard idx.dids.contains(did) else { throw AccountError.unknownAccount(did) }
        idx.currentDID = did
        try writeIndex(idx)
    }

    /// Remove an account, its index entry, and clear `currentDID` if it pointed here.
    public func remove(did: String) throws {
        try storage.remove(for: accountKey(did))
        var idx = try index()
        idx.dids.removeAll { $0 == did }
        if idx.currentDID == did { idx.currentDID = nil }
        try writeIndex(idx)
    }
}

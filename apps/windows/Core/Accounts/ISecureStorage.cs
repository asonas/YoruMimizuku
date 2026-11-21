namespace YoruMimizuku.Core.Accounts;

/// <summary>
/// Encrypted key/value storage for accounts: their tokens and DPoP private keys.
/// The app uses <see cref="DpapiFileStorage"/>; tests use an in-memory store.
/// </summary>
public interface ISecureStorage
{
    /// <summary>The value stored under <paramref name="key"/>, or null when there is none.</summary>
    byte[]? Read(string key);

    /// <summary>Stores <paramref name="value"/>, replacing any value under <paramref name="key"/>.</summary>
    void Write(string key, byte[] value);

    /// <summary>Removes the value under <paramref name="key"/>; nothing happens when there is none.</summary>
    void Delete(string key);
}

namespace YoruMimizuku.Core.Accounts;

/// <summary>
/// The Swift core's DPAPI store, which the C# core never reads: accounts.index and one
/// account.&lt;did&gt; per signed-in account, each a hex-named .bin file. Phase 4 has the
/// app delete it at launch and tell the user once that they need to sign in again.
/// </summary>
public static class LegacySwiftAccountStore
{
    /// <summary>The hex of "account.", which starts every account file and not the index.</summary>
    private const string AccountFilePattern = "6163636f756e742e*.bin";

    /// <summary>%LOCALAPPDATA%\as.ason.YoruMimizuku\secure, where the Swift DPAPISecureStorage wrote.</summary>
    public static string DefaultDirectory() => Path.Combine(LocalAppData.Directory(),"as.ason.YoruMimizuku", "secure");

    /// <summary>
    /// Deletes <paramref name="directory"/> if it exists. True when it held a signed-in
    /// account, which is when to tell the user; the next launch finds nothing and is false.
    /// </summary>
    public static bool DeleteIfPresent(string directory)
    {
        if (!Directory.Exists(directory)) return false;
        var signedIn = Directory.EnumerateFiles(directory, AccountFilePattern).Any();
        Directory.Delete(directory, recursive: true);
        return signedIn;
    }
}

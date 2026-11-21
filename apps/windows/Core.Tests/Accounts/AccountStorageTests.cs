using System.Text;
using YoruMimizuku.Core.Accounts;

namespace YoruMimizuku.Core.Tests;

public sealed class AccountStorageTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("yoru-storage-").FullName;

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true);
    }

    [Fact]
    public void DpapiStorageRoundTripsWithoutPlaintextOnDisk()
    {
        if (!OperatingSystem.IsWindows()) return;
        var storage = new DpapiFileStorage(_directory);
        var secret = Encoding.UTF8.GetBytes("""{"accessToken":"secret-access-token"}""");

        Assert.Null(storage.Read("account.did:plc:alice"));
        storage.Write("account.did:plc:alice", secret);

        Assert.Equal(secret, storage.Read("account.did:plc:alice"));
        var file = Assert.Single(Directory.GetFiles(_directory));
        Assert.DoesNotContain("secret-access-token", Encoding.UTF8.GetString(File.ReadAllBytes(file)));
        storage.Delete("account.did:plc:alice");
        Assert.Null(storage.Read("account.did:plc:alice"));
        Assert.Empty(Directory.GetFiles(_directory));
    }

    [Fact]
    public void TheCSharpStoreNeverSharesTheSwiftStoresDirectory()
    {
        if (!OperatingSystem.IsWindows()) return;

        Assert.NotEqual(
            Path.GetFullPath(LegacySwiftAccountStore.DefaultDirectory()),
            Path.GetFullPath(DpapiFileStorage.DefaultDirectory()),
            StringComparer.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(true, true, true)]
    [InlineData(true, false, false)]
    [InlineData(false, false, false)]
    public void DeletingTheSwiftStoreReportsWhetherAnAccountWasSignedIn(bool directoryExists, bool hasAccount, bool signedIn)
    {
        var swift = Path.Combine(_directory, "secure");
        if (directoryExists)
        {
            Directory.CreateDirectory(swift);
            File.WriteAllBytes(Path.Combine(swift, SwiftFileName("accounts.index")), [1]);
            if (hasAccount) File.WriteAllBytes(Path.Combine(swift, SwiftFileName("account.did:plc:alice")), [1]);
        }

        Assert.Equal(signedIn, LegacySwiftAccountStore.DeleteIfPresent(swift));
        Assert.False(Directory.Exists(swift));
    }

    /// <summary>How the Swift DPAPISecureStorage names a key's file: hex of the UTF-8 key, then .bin.</summary>
    private static string SwiftFileName(string key) => Convert.ToHexStringLower(Encoding.UTF8.GetBytes(key)) + ".bin";
}

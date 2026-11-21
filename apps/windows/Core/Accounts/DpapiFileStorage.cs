using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;

namespace YoruMimizuku.Core.Accounts;

/// <summary>
/// <see cref="ISecureStorage"/> as one DPAPI-encrypted file per key, readable only by
/// the current Windows user. File names are the hex of the key, since DIDs hold ':'.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class DpapiFileStorage(string directory) : ISecureStorage
{
    /// <summary>
    /// %LOCALAPPDATA%\YoruMimizuku\accounts, beside the app's settings and saved filters
    /// and apart from the Swift core's store, so its files are never misread.
    /// </summary>
    public static string DefaultDirectory() => Path.Combine(LocalAppData.Directory(), "YoruMimizuku", "accounts");

    public byte[]? Read(string key)
    {
        var path = PathFor(key);
        return File.Exists(path) ? ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser) : null;
    }

    public void Write(string key, byte[] value)
    {
        Directory.CreateDirectory(directory);
        var path = PathFor(key);
        var temporary = $"{path}.{Guid.NewGuid():N}.tmp";
        File.WriteAllBytes(temporary, ProtectedData.Protect(value, null, DataProtectionScope.CurrentUser));
        File.Move(temporary, path, overwrite: true);
    }

    public void Delete(string key) => File.Delete(PathFor(key));

    /// <summary>
    /// Holds the key's ".lock" file open with no sharing. Windows releases it when the
    /// holder disposes it or its process ends, so a crashed app never leaves it locked.
    /// </summary>
    public async Task<IAsyncDisposable> LockAsync(string key, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(directory);
        var path = PathFor(key) + ".lock";
        while (true)
        {
            try
            {
                return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException) when (File.Exists(path))
            {
                await Task.Delay(LockRetryDelay, cancellationToken);
            }
        }
    }

    private static readonly TimeSpan LockRetryDelay = TimeSpan.FromMilliseconds(50);

    private string PathFor(string key) => Path.Combine(directory, Convert.ToHexStringLower(Encoding.UTF8.GetBytes(key)) + ".bin");
}

internal static class LocalAppData
{
    /// <summary>
    /// %LOCALAPPDATA%, falling back to its environment variable when the known-folder
    /// lookup fails, as the app's settings do. Without either it throws rather than let
    /// tokens land in a relative directory.
    /// </summary>
    public static string Directory()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrEmpty(root)) root = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        return string.IsNullOrEmpty(root) ? throw new InvalidOperationException("%LOCALAPPDATA% cannot be found.") : root;
    }
}

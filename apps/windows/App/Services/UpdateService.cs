using System;
using System.Reflection;
using YoruMimizuku.App.Interop;

namespace YoruMimizuku.App.Services;

public sealed class UpdateService
{
    // TODO: Replace with the WinSparkle EdDSA public key generated for Windows.
    private const string PublicKeyPlaceholder = "__REPLACE_WITH_WINSPARKLE_PUBLIC_ED25519_KEY__";

    public static UpdateService Shared { get; } = new();

    public bool IsConfigured => !string.Equals(
        PublicKeyPlaceholder,
        "__REPLACE_WITH_WINSPARKLE_PUBLIC_ED25519_KEY__",
        StringComparison.Ordinal);
    public bool IsInitialized { get; private set; }

    public Uri StableFeedUrl { get; } = new("https://asonas.github.io/YoruMimizuku/appcast-windows.xml");
    public Uri DevelopmentFeedUrl { get; } = new("https://asonas.github.io/YoruMimizuku/appcast-windows-dev.xml");

    public Uri CurrentFeedUrl => AppSettings.Shared.UpdateChannel == WindowsUpdateChannel.Development
        ? DevelopmentFeedUrl
        : StableFeedUrl;

    public string VersionDisplay
    {
        get
        {
            var info = Assembly.GetExecutingAssembly()
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
                .InformationalVersion;
            if (!string.IsNullOrWhiteSpace(info))
            {
                return info.StartsWith('v') ? info : "v" + info;
            }
            var version = Assembly.GetExecutingAssembly().GetName().Version;
            return version is null ? "Unknown" : $"v{version.Major}.{version.Minor}.{version.Build}";
        }
    }

    private UpdateService() { }

    public void Initialize()
    {
        if (IsInitialized || !IsConfigured) return;
        try
        {
            WinSparkleNative.win_sparkle_set_appcast_url(CurrentFeedUrl.AbsoluteUri);
            WinSparkleNative.win_sparkle_set_app_details("asonas", "YoruMimizuku", VersionDisplay.TrimStart('v'));
            WinSparkleNative.win_sparkle_set_app_build_version(VersionDisplay.TrimStart('v'));
            WinSparkleNative.win_sparkle_set_registry_path("Software\\YoruMimizuku\\Updates");
            var validKey = WinSparkleNative.win_sparkle_set_eddsa_public_key(PublicKeyPlaceholder);
            if (validKey == 0)
            {
                AppLog.Write("WinSparkle public key rejected; updater disabled.");
                return;
            }
            WinSparkleNative.win_sparkle_set_automatic_check_for_updates(
                AppSettings.Shared.AutomaticallyChecksForUpdates ? 1 : 0);
            WinSparkleNative.win_sparkle_init();
            IsInitialized = true;
        }
        catch (Exception ex)
        {
            AppLog.Write("WinSparkle initialize failed", ex);
        }
    }

    public void CheckForUpdates()
    {
        if (!IsInitialized) Initialize();
        if (!IsInitialized) return;
        try
        {
            WinSparkleNative.win_sparkle_check_update_with_ui();
        }
        catch (Exception ex)
        {
            AppLog.Write("WinSparkle check failed", ex);
        }
    }

    public void Shutdown()
    {
        if (!IsInitialized) return;
        try
        {
            WinSparkleNative.win_sparkle_cleanup();
        }
        catch (Exception ex)
        {
            AppLog.Write("WinSparkle cleanup failed", ex);
        }
        finally
        {
            IsInitialized = false;
        }
    }
}

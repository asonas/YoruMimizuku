using System;
using System.IO;
using System.Net.Http;
using Microsoft.UI.Xaml;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Services;
using YoruMimizuku.Core.Accounts;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.App;

public partial class App : Application
{
    // Must stay in sync with the published client-metadata.json and the macOS
    // OAuthClientConfig.yoruMimizuku values.
    public const string Service = "as.ason.YoruMimizuku";
    public const string ClientId = "https://ason.as/yorumimizuku/client-metadata.json";
    public const string RedirectUri = "as.ason:/callback";
    public const string Scope = "atproto transition:generic";

    /// <summary>The core every window talks to.</summary>
    public static ICoreClient Client { get; } = new CoreClient(
        new DpapiFileStorage(DpapiFileStorage.DefaultDirectory()), new SocketsHttpHandler(), OAuthClientConfig.YoruMimizuku);

    private Window? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            AppLog.Write("UnhandledException", e.Exception);
            // Keep the process alive so the error surfaces in the window instead of
            // a silent crash + Program Compatibility Assistant.
            e.Handled = true;
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        AppLog.Write("OnLaunched");
        var swiftAccountsRemoved = RemoveSwiftAccounts();
        // Create and show the window first; it loads the stored account itself so
        // any failure is shown in the UI (and logged) rather than crashing before
        // a window exists.
        var mainWindow = new MainWindow();
        _window = mainWindow;
        _window.Activate();
        // Restore AFTER Activate: the first Activate applies WinUI's default window
        // size, so applying the saved placement before it gets overwritten (which is
        // why the earlier width-only restore never stuck).
        mainWindow.RestoreSavedWindowPlacement();
        if (swiftAccountsRemoved) mainWindow.ShowSignInAgainNotice();
        UpdateService.Shared.Initialize();
    }

    /// <summary>
    /// The C# core never reads the Swift core's store, so its first launch deletes it.
    /// True when an account was signed in there; the next launch finds nothing, so the
    /// notice is shown once. A failure is logged and retried at the next launch.
    /// </summary>
    private static bool RemoveSwiftAccounts()
    {
        try
        {
            return LegacySwiftAccountStore.DeleteIfPresent(LegacySwiftAccountStore.DefaultDirectory());
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            AppLog.Write("removing the Swift account store failed", ex);
            return false;
        }
    }
}

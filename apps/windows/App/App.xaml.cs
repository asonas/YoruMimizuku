using Microsoft.UI.Xaml;
using YoruMimizuku.App.Services;

namespace YoruMimizuku.App;

public partial class App : Application
{
    // Must stay in sync with the published client-metadata.json and the macOS
    // OAuthClientConfig.yoruMimizuku values.
    public const string Service = "as.ason.YoruMimizuku";
    public const string ClientId = "https://ason.as/yorumimizuku/client-metadata.json";
    public const string RedirectUri = "as.ason:/callback";
    public const string Scope = "atproto transition:generic";

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
        // Create and show the window first; the bridge is initialized inside it so
        // any failure is shown in the UI (and logged) rather than crashing before
        // a window exists.
        var mainWindow = new MainWindow();
        _window = mainWindow;
        _window.Activate();
        // Restore AFTER Activate: the first Activate applies WinUI's default window
        // size, so applying the saved placement before it gets overwritten (which is
        // why the earlier width-only restore never stuck).
        mainWindow.RestoreSavedWindowPlacement();
        UpdateService.Shared.Initialize();
    }
}

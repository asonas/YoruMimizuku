using Microsoft.UI.Xaml;
using YoruMimizuku.App.Interop;

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
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Configure the Swift core bridge before any feature call.
        await BridgeClient.Shared.InitializeAsync(Service, ClientId, RedirectUri, Scope);

        _window = new MainWindow();
        _window.Activate();
    }
}

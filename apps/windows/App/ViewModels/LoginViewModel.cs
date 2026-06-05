using System;
using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

/// <summary>
/// Two-step OAuth login for the WebView2 flow: <see cref="BeginAsync"/> produces
/// the authorization URL to load in the WebView, and <see cref="CompleteAsync"/>
/// finishes the token exchange once the redirect to the callback scheme is seen.
/// </summary>
public sealed class LoginViewModel : ObservableObject
{
    private string _handle = "";
    public string Handle { get => _handle; set { if (SetProperty(ref _handle, value)) OnPropertyChanged(nameof(CanSubmit)); } }

    private bool _isBusy;
    public bool IsBusy { get => _isBusy; private set { if (SetProperty(ref _isBusy, value)) OnPropertyChanged(nameof(CanSubmit)); } }

    private string? _errorMessage;
    public string? ErrorMessage { get => _errorMessage; private set => SetProperty(ref _errorMessage, value); }

    public string? AuthUrl { get; private set; }
    public string? CallbackScheme { get; private set; }
    private string? _pendingId;

    public bool CanSubmit => !IsBusy && Handle.Trim().Length > 0;

    /// <summary>Raised with the account DID once login completes successfully.</summary>
    public event Action<string>? Authenticated;

    public async Task BeginAsync()
    {
        if (!CanSubmit) return;
        IsBusy = true;
        ErrorMessage = null;
        try
        {
            var begin = await BridgeClient.Shared.LoginBeginAsync(Handle.Trim());
            _pendingId = begin.PendingId;
            AuthUrl = begin.AuthUrl;
            CallbackScheme = begin.CallbackScheme;
            OnPropertyChanged(nameof(AuthUrl));
            OnPropertyChanged(nameof(CallbackScheme));
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
            IsBusy = false;
        }
    }

    /// <summary>Returns true if <paramref name="url"/> is the OAuth callback redirect.</summary>
    public bool IsCallback(string url) =>
        CallbackScheme is not null && url.StartsWith(CallbackScheme + ":", StringComparison.OrdinalIgnoreCase);

    public async Task CompleteAsync(string callbackUrl)
    {
        if (_pendingId is null) return;
        try
        {
            var account = await BridgeClient.Shared.LoginCompleteAsync(_pendingId, callbackUrl);
            Authenticated?.Invoke(account.Did);
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }
}

using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class LoginView : UserControl
{
    private readonly LoginViewModel _vm = new();

    public event Action<string>? Authenticated;

    public LoginView()
    {
        InitializeComponent();
        _vm.Authenticated += did => Authenticated?.Invoke(did);
    }

    private async void OnSignInClick(object sender, RoutedEventArgs e)
    {
        _vm.Handle = HandleBox.Text;
        ShowError(null);
        Spinner.IsActive = true;
        SignInButton.IsEnabled = false;

        await _vm.BeginAsync();

        if (_vm.ErrorMessage is not null)
        {
            ShowError(_vm.ErrorMessage);
            Spinner.IsActive = false;
            SignInButton.IsEnabled = true;
            return;
        }
        await StartWebAuthAsync();
    }

    private async System.Threading.Tasks.Task StartWebAuthAsync()
    {
        if (_vm.AuthUrl is null) return;
        EntryPanel.Visibility = Visibility.Collapsed;
        AuthWeb.Visibility = Visibility.Visible;

        await AuthWeb.EnsureCoreWebView2Async();
        AuthWeb.CoreWebView2.NavigationStarting += OnNavigationStarting;
        AuthWeb.Source = new Uri(_vm.AuthUrl);
    }

    private async void OnNavigationStarting(CoreWebView2 sender, CoreWebView2NavigationStartingEventArgs args)
    {
        if (_vm.IsCallback(args.Uri))
        {
            // Stop the WebView from trying to load the custom scheme, finish the
            // token exchange, and surface any error back on the entry panel.
            args.Cancel = true;
            await _vm.CompleteAsync(args.Uri);
            if (_vm.ErrorMessage is not null)
            {
                AuthWeb.Visibility = Visibility.Collapsed;
                EntryPanel.Visibility = Visibility.Visible;
                ShowError(_vm.ErrorMessage);
                Spinner.IsActive = false;
                SignInButton.IsEnabled = true;
            }
        }
    }

    private void ShowError(string? message)
    {
        ErrorText.Text = message ?? "";
        ErrorText.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
    }
}

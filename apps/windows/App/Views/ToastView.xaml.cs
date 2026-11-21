using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using YoruMimizuku.App.Services;

namespace YoruMimizuku.App.Views;

/// <summary>Shows <see cref="ToastCenter"/>'s message when it was raised in this window.</summary>
public sealed partial class ToastView : UserControl
{
    public ToastView()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            ToastCenter.Shared.MessageChanged += UpdateMessage;
            UpdateMessage();
        };
        Unloaded += (_, _) => ToastCenter.Shared.MessageChanged -= UpdateMessage;
    }

    private void UpdateMessage()
    {
        var center = ToastCenter.Shared;
        var mine = center.Message is not null && ReferenceEquals(center.Origin, XamlRoot);
        MessageText.Text = mine ? center.Message : "";
        ToastBorder.Visibility = mine ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnToastTapped(object sender, TappedRoutedEventArgs e)
    {
        ToastCenter.Shared.Dismiss();
        e.Handled = true;
    }
}

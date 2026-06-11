using Microsoft.UI.Xaml.Controls;
using YoruMimizuku.App.Services;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class SettingsView : UserControl
{
    private readonly UpdateSettingsViewModel _updates = new();
    private bool _initializing;

    public SettingsView()
    {
        _initializing = true;
        InitializeComponent();
        DensityChoice.SelectedIndex = AppSettings.Shared.Density == DisplayDensity.Compact ? 0 : 1;
        FontSlider.Value = AppSettings.Shared.FontSize;
        VersionText.Text = "現在のバージョン: " + _updates.CurrentVersion;
        AutoUpdateCheck.IsChecked = _updates.AutomaticallyChecksForUpdates;
        UpdateChannelBox.SelectedIndex = _updates.ChannelIndex;
        RefreshUpdateStatus();
        _initializing = false;
    }

    private void OnDensityChanged(object sender, SelectionChangedEventArgs e)
    {
        AppSettings.Shared.Density = DensityChoice.SelectedIndex == 0 ? DisplayDensity.Compact : DisplayDensity.Comfortable;
    }

    private void OnApplyThemeClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (ThemeService.TryParseRandomA11yUrl(ThemeUrlBox.Text, out var background, out var text))
        {
            ThemeService.Shared.Apply(background, text);
        }
    }

    private void OnResetThemeClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        ThemeService.Shared.Reset();
    }

    private void OnFontSizeChanged(object sender, Microsoft.UI.Xaml.Controls.Primitives.RangeBaseValueChangedEventArgs e)
    {
        AppSettings.Shared.FontSize = e.NewValue;
    }

    private void OnAutoUpdateChanged(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_initializing) return;
        _updates.AutomaticallyChecksForUpdates = AutoUpdateCheck.IsChecked == true;
        RefreshUpdateStatus();
    }

    private void OnUpdateChannelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_initializing || UpdateChannelBox.SelectedIndex < 0) return;
        _updates.ChannelIndex = UpdateChannelBox.SelectedIndex;
        RefreshUpdateStatus();
    }

    private void OnCheckUpdatesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        _updates.CheckNow();
        RefreshUpdateStatus();
    }

    private void RefreshUpdateStatus()
    {
        UpdateStatusText.Text = _updates.StatusText;
    }
}

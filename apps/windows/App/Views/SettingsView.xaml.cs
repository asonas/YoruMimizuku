using Microsoft.UI.Xaml.Controls;
using YoruMimizuku.App.Services;

namespace YoruMimizuku.App.Views;

public sealed partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        DensityChoice.SelectedIndex = AppSettings.Shared.Density == DisplayDensity.Compact ? 0 : 1;
        FontSlider.Value = AppSettings.Shared.FontSize;
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
}

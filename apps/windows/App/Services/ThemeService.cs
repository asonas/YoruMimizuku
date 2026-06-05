using System;
using System.Text.RegularExpressions;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace YoruMimizuku.App.Services;

/// <summary>
/// Applies a two-colour palette (background + text) to the app's brush resources,
/// mirroring the macOS randoma11y theming. The default is the monochrome palette
/// (white background, near-black text).
/// </summary>
public sealed class ThemeService
{
    public static ThemeService Shared { get; } = new();

    private static readonly Color DefaultBackground = Color.FromArgb(255, 255, 255, 255);
    private static readonly Color DefaultText = Color.FromArgb(255, 17, 17, 17);

    public void Apply(Color background, Color text)
    {
        var resources = Application.Current.Resources;
        resources["AppBackgroundBrush"] = new SolidColorBrush(background);
        resources["AppTextBrush"] = new SolidColorBrush(text);
    }

    public void Reset() => Apply(DefaultBackground, DefaultText);

    /// <summary>
    /// Extract the first two hex colours from a randoma11y URL (background then
    /// text). Accepts <c>#RRGGBB</c> or bare <c>RRGGBB</c> tokens.
    /// </summary>
    public static bool TryParseRandomA11yUrl(string url, out Color background, out Color text)
    {
        background = DefaultBackground;
        text = DefaultText;
        if (string.IsNullOrWhiteSpace(url)) return false;

        var matches = Regex.Matches(url, "#?([0-9a-fA-F]{6})");
        if (matches.Count < 2) return false;
        background = HexToColor(matches[0].Groups[1].Value);
        text = HexToColor(matches[1].Groups[1].Value);
        return true;
    }

    private static Color HexToColor(string hex)
    {
        var r = Convert.ToByte(hex.Substring(0, 2), 16);
        var g = Convert.ToByte(hex.Substring(2, 2), 16);
        var b = Convert.ToByte(hex.Substring(4, 2), 16);
        return Color.FromArgb(255, r, g, b);
    }
}

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
        // Blend neutral text shades from the pair so they read on any background.
        resources["AppSecondaryTextBrush"] = new SolidColorBrush(Blend(text, background, 0.30));
        resources["AppTertiaryTextBrush"] = new SolidColorBrush(Blend(text, background, 0.50));
        resources["AppHairlineBrush"] = new SolidColorBrush(WithAlpha(text, 0x1A));
        resources["AppRowHoverBrush"] = new SolidColorBrush(WithAlpha(text, 0x0D));
        AppSettings.Shared.ThemePair = $"{Hex(background)}|{Hex(text)}";
    }

    public void Reset()
    {
        AppSettings.Shared.ThemePair = null;
        Apply(DefaultBackground, DefaultText);
        AppSettings.Shared.ThemePair = null;
    }

    /// Apply the persisted palette (or the default) at startup.
    public void ApplySaved()
    {
        var pair = AppSettings.Shared.ThemePair;
        if (pair is { } p && p.Split('|') is { Length: 2 } parts)
        {
            Apply(HexToColor(parts[0]), HexToColor(parts[1]));
        }
        else
        {
            Apply(DefaultBackground, DefaultText);
        }
    }

    private static Color Blend(Color a, Color b, double t) => Color.FromArgb(
        255,
        (byte)(a.R + (b.R - a.R) * t),
        (byte)(a.G + (b.G - a.G) * t),
        (byte)(a.B + (b.B - a.B) * t));

    private static Color WithAlpha(Color c, byte a) => Color.FromArgb(a, c.R, c.G, c.B);

    private static string Hex(Color c) => $"{c.R:X2}{c.G:X2}{c.B:X2}";

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

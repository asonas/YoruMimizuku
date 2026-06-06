using System;
using System.Globalization;

namespace YoruMimizuku.App.Services;

/// <summary>
/// Short relative timestamps ("now", "30s", "2m", "3h", "2d"), matching the Swift
/// RelativeTimeFormatter so the Windows timeline reads like the macOS one.
/// </summary>
public static class RelativeTime
{
    public static string Format(string isoCreatedAt) => Format(isoCreatedAt, DateTimeOffset.Now);

    public static string Format(string isoCreatedAt, DateTimeOffset now)
    {
        if (!DateTimeOffset.TryParse(isoCreatedAt, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var created))
        {
            return "";
        }
        var seconds = (int)(now - created).TotalSeconds;
        if (seconds < 5) return "now";
        if (seconds < 60) return $"{seconds}s";
        var minutes = seconds / 60;
        if (minutes < 60) return $"{minutes}m";
        var hours = minutes / 60;
        if (hours < 24) return $"{hours}h";
        var days = hours / 24;
        return $"{days}d";
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Globalization;

namespace YoruMimizuku.App.Services;

public enum DisplayDensity { Compact, Comfortable }
public enum WindowsUpdateChannel { Stable, Development }

/// <summary>
/// App-local preferences (density, font size, theme) persisted as JSON under
/// %LOCALAPPDATA%\YoruMimizuku\settings.json.
///
/// Backed by a file rather than <c>ApplicationData.Current</c>, which is only
/// available to packaged apps and throws in an unpackaged WinUI app.
/// </summary>
public sealed class AppSettings
{
    public static AppSettings Shared { get; } = new();

    // A computed property, NOT a static field: as a field it is initialized in
    // textual order *after* `Shared` above, so the `Shared = new()` constructor ran
    // `Load()` while FilePath was still null — `File.Exists(null)` is false, so every
    // launch loaded an empty dict and then re-saved only the default theme, silently
    // wiping density / font size / window placement. Computing it on each access
    // removes the initialization-order dependency.
    private static string FilePath => Path.Combine(
        LocalAppDataDir(), "YoruMimizuku", "settings.json");

    /// Resolve %LOCALAPPDATA% robustly. <c>Environment.GetFolderPath</c> can return
    /// an empty string when the known-folder API fails (e.g. a process launched
    /// without a fully loaded user profile); an empty base would make
    /// <see cref="FilePath"/> relative, so Load/Save silently target the working
    /// directory and every launch loses the saved settings. Fall back to the
    /// LOCALAPPDATA env var, then USERPROFILE, so the path is always absolute.
    private static string LocalAppDataDir()
    {
        var dir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (!string.IsNullOrEmpty(dir)) return dir;

        dir = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        if (!string.IsNullOrEmpty(dir)) return dir;

        var profile = Environment.GetEnvironmentVariable("USERPROFILE");
        return string.IsNullOrEmpty(profile) ? "" : Path.Combine(profile, "AppData", "Local");
    }

    private readonly object _gate = new();
    private Dictionary<string, string> _values;

    /// Raised when a notification setting (poll interval / badge visibility) changes,
    /// so the shell can re-apply the timer interval and badge display live.
    public event Action? NotificationSettingsChanged;

    private AppSettings()
    {
        _values = Load();
    }

    public DisplayDensity Density
    {
        get => Get("density") == "comfortable" ? DisplayDensity.Comfortable : DisplayDensity.Compact;
        set => Set("density", value == DisplayDensity.Comfortable ? "comfortable" : "compact");
    }

    public double FontSize
    {
        get => double.TryParse(Get("fontSize"), out var d) ? d : 14.0;
        set => Set("fontSize", value.ToString(CultureInfo.InvariantCulture));
    }

    /// Serialized Win32 window placement ("showCmd,left,top,right,bottom"),
    /// produced by <see cref="WindowPlacement"/>. Captures position, size, and the
    /// maximized state so the window relaunches where the user left it; null until
    /// a window has been shown and closed at least once.
    public string? WindowPlacement
    {
        get => Get("windowPlacement");
        set => Set("windowPlacement", value);
    }

    public WindowsUpdateChannel UpdateChannel
    {
        get => Get("updates.channel") == "development" ? WindowsUpdateChannel.Development : WindowsUpdateChannel.Stable;
        set => Set("updates.channel", value == WindowsUpdateChannel.Development ? "development" : "stable");
    }

    public bool AutomaticallyChecksForUpdates
    {
        get => Get("updates.automaticChecks") != "false";
        set => Set("updates.automaticChecks", value ? "true" : "false");
    }

    /// Notification poll interval in seconds, snapped to the supported set
    /// (15 / 30 / 60 / 300; default 30) — mirrors the macOS NotificationSettingsStore.
    public int NotificationPollIntervalSeconds
    {
        get
        {
            var value = int.TryParse(Get("notifications.pollIntervalSeconds"), out var n) ? n : 30;
            return value is 15 or 30 or 60 or 300 ? value : 30;
        }
        set { Set("notifications.pollIntervalSeconds", value.ToString(CultureInfo.InvariantCulture)); NotificationSettingsChanged?.Invoke(); }
    }

    /// Whether the sidebar/tab unread badge is shown (default on). When off, counts
    /// are still tracked but never displayed.
    public bool ShowsUnreadBadges
    {
        get => Get("notifications.showsUnreadBadges") != "false";
        set { Set("notifications.showsUnreadBadges", value ? "true" : "false"); NotificationSettingsChanged?.Invoke(); }
    }

    /// Persisted theme as "RRGGBB|RRGGBB" (background|text); null = default palette.
    public string? ThemePair
    {
        get => Get("themePair");
        set => Set("themePair", value);
    }

    private string? Get(string key)
    {
        lock (_gate) return _values.TryGetValue(key, out var v) ? v : null;
    }

    private void Set(string key, string? value)
    {
        lock (_gate)
        {
            if (value is null) _values.Remove(key);
            else _values[key] = value;
            Save();
        }
    }

    private static Dictionary<string, string> Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var json = File.ReadAllText(FilePath);
                return JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new();
            }
        }
        catch (Exception ex) { AppLog.Write("settings load failed", ex); }
        return new();
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(_values));
        }
        catch (Exception ex) { AppLog.Write("settings save failed", ex); }
    }
}

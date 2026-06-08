using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Globalization;

namespace YoruMimizuku.App.Services;

public enum DisplayDensity { Compact, Comfortable }

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

    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "YoruMimizuku", "settings.json");

    private readonly object _gate = new();
    private Dictionary<string, string> _values;

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

    public double? WindowWidth
    {
        get => double.TryParse(Get("windowWidth"), NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : null;
        set => Set("windowWidth", value?.ToString(CultureInfo.InvariantCulture));
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

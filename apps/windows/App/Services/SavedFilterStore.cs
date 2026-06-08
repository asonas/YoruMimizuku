using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Services;

/// <summary>
/// Per-account saved-filter persistence for the unpackaged WinUI app.
/// </summary>
public sealed class SavedFilterStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private readonly string _filePath;

    public SavedFilterStore(string did)
    {
        var fileName = "filters-" + SafeFileName(did) + ".json";
        _filePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YoruMimizuku",
            fileName);
    }

    public IReadOnlyList<SavedFilterModel> Load()
    {
        try
        {
            if (!File.Exists(_filePath)) return Array.Empty<SavedFilterModel>();
            var json = File.ReadAllText(_filePath);
            return JsonSerializer.Deserialize<List<SavedFilterModel>>(json, JsonOptions) ?? new();
        }
        catch (Exception ex)
        {
            AppLog.Write("filters load failed", ex);
            return Array.Empty<SavedFilterModel>();
        }
    }

    public void Save(IEnumerable<SavedFilterModel> filters)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
            File.WriteAllText(_filePath, JsonSerializer.Serialize(filters, JsonOptions));
        }
        catch (Exception ex)
        {
            AppLog.Write("filters save failed", ex);
        }
    }

    private static string SafeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        foreach (var ch in invalid)
        {
            value = value.Replace(ch, '_');
        }
        return value;
    }
}

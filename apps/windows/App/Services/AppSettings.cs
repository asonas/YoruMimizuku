using Windows.Storage;

namespace YoruMimizuku.App.Services;

public enum DisplayDensity { Compact, Comfortable }

/// <summary>Lightweight app-local preferences (density, font size) persisted to
/// the WinUI ApplicationData local settings.</summary>
public sealed class AppSettings
{
    public static AppSettings Shared { get; } = new();

    private readonly ApplicationDataContainer _store = ApplicationData.Current.LocalSettings;

    public DisplayDensity Density
    {
        get => (_store.Values["density"] as string) == "comfortable" ? DisplayDensity.Comfortable : DisplayDensity.Compact;
        set => _store.Values["density"] = value == DisplayDensity.Comfortable ? "comfortable" : "compact";
    }

    public double FontSize
    {
        get => _store.Values["fontSize"] is double d ? d : 14.0;
        set => _store.Values["fontSize"] = value;
    }
}

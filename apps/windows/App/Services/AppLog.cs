using System;
using System.IO;

namespace YoruMimizuku.App.Services;

/// <summary>
/// Minimal append-only file logger so startup/runtime failures leave a trace even
/// when the app crashes before any UI is shown. Writes to
/// %LOCALAPPDATA%\YoruMimizuku\app.log.
/// </summary>
public static class AppLog
{
    private static readonly object Gate = new();

    public static string Path { get; } = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "YoruMimizuku", "app.log");

    public static void Write(string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
                File.AppendAllText(Path, $"{DateTimeOffset.Now:o} {message}{Environment.NewLine}");
            }
        }
        catch { /* logging must never throw */ }
    }

    public static void Write(string context, Exception ex) =>
        Write($"{context}: {ex.GetType().Name}: {ex.Message}\n{ex}");
}

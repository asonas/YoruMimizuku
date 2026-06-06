using System;
using System.IO;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace YoruMimizuku.App.Services;

/// <summary>Sets the window/taskbar icon from the bundled Assets\AppIcon.ico.</summary>
public static class AppIcon
{
    public static void TrySetWindowIcon(Window window)
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
            if (!File.Exists(path)) return;
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            var id = Win32Interop.GetWindowIdFromWindow(hwnd);
            AppWindow.GetFromWindowId(id).SetIcon(path);
        }
        catch (Exception ex)
        {
            AppLog.Write("set window icon failed", ex);
        }
    }
}

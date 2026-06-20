using System;
using System.Globalization;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace YoruMimizuku.App.Services;

/// <summary>
/// Persists and restores a top-level window's placement (normal position, size,
/// and maximized state) via the Win32 <c>GetWindowPlacement</c> /
/// <c>SetWindowPlacement</c> APIs.
///
/// WinUI 3 / AppWindow does not expose placement persistence, and a width-only
/// <c>AppWindow.Resize</c> mixes DPI units (AppWindow.Size is physical pixels,
/// WindowSizeChanged is DIPs) which fight each other on High-DPI displays.
/// <c>WINDOWPLACEMENT</c> sidesteps both: it captures left/top/right/bottom plus
/// the show command in DPI-consistent workspace coordinates and restores them in
/// one call, including whether the window was maximized.
/// </summary>
public static class WindowPlacement
{
    // showCmd values (winuser.h). We only persist/restore Normal and Maximized;
    // a minimized window is restored to its normal placement instead.
    private const int SW_SHOWNORMAL = 1;
    private const int SW_SHOWMINIMIZED = 2;
    private const int SW_SHOWMAXIMIZED = 3;
    private const int SW_MINIMIZE = 6;
    private const int SW_SHOWMINNOACTIVE = 7;

    /// Read the window's current placement and return it as a compact,
    /// settings-friendly string ("showCmd,left,top,right,bottom"), or null if it
    /// cannot be read. A minimized window is normalized to SW_SHOWNORMAL so the
    /// app never relaunches into the taskbar.
    public static string? Capture(Window window)
    {
        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            var placement = WINDOWPLACEMENT.Create();
            if (!GetWindowPlacement(hwnd, ref placement)) return null;

            var showCmd = placement.showCmd;
            if (showCmd is SW_SHOWMINIMIZED or SW_MINIMIZE or SW_SHOWMINNOACTIVE)
                showCmd = SW_SHOWNORMAL;

            var r = placement.rcNormalPosition;
            // A zero-area normal rect means the window was never laid out; skip it
            // so we do not persist a degenerate placement.
            if (r.right <= r.left || r.bottom <= r.top) return null;

            return string.Create(CultureInfo.InvariantCulture,
                $"{showCmd},{r.left},{r.top},{r.right},{r.bottom}");
        }
        catch (Exception ex)
        {
            AppLog.Write("capture window placement failed", ex);
            return null;
        }
    }

    /// Apply a placement previously produced by <see cref="Capture"/>. Returns
    /// false (and leaves the window untouched) for malformed input or a
    /// degenerate rect, so callers fall back to the default window size.
    public static bool Apply(Window window, string? saved)
    {
        if (string.IsNullOrWhiteSpace(saved)) return false;
        var parts = saved.Split(',');
        if (parts.Length != 5) return false;

        var values = new int[5];
        for (var i = 0; i < 5; i++)
        {
            if (!int.TryParse(parts[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out values[i]))
                return false;
        }

        var (showCmd, left, top, right, bottom) = (values[0], values[1], values[2], values[3], values[4]);
        if (right <= left || bottom <= top) return false;
        if (showCmd is not (SW_SHOWNORMAL or SW_SHOWMAXIMIZED)) showCmd = SW_SHOWNORMAL;

        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            var placement = WINDOWPLACEMENT.Create();
            placement.showCmd = showCmd;
            placement.rcNormalPosition = new RECT { left = left, top = top, right = right, bottom = bottom };
            return SetWindowPlacement(hwnd, ref placement);
        }
        catch (Exception ex)
        {
            AppLog.Write("apply window placement failed", ex);
            return false;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WINDOWPLACEMENT
    {
        public int length;
        public int flags;
        public int showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public RECT rcNormalPosition;

        public static WINDOWPLACEMENT Create() => new() { length = Marshal.SizeOf<WINDOWPLACEMENT>() };
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
}

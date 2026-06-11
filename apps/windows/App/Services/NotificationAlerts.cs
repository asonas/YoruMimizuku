using System;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace YoruMimizuku.App.Services;

/// <summary>
/// OS-level notification surface for Windows: a toast banner via the Windows App
/// SDK <see cref="AppNotificationManager"/> (works for the unpackaged app) plus a
/// taskbar attention flash via FlashWindowEx — the Windows analogue of the macOS
/// OS banner. A persistent numeric taskbar badge needs packaged (MSIX) identity,
/// which is future work; the in-app unread tab badge covers the count meanwhile.
/// </summary>
public sealed class NotificationAlerts
{
    public static NotificationAlerts Shared { get; } = new();

    private bool _registered;

    public void Register()
    {
        if (_registered) return;
        try { AppNotificationManager.Default.Register(); _registered = true; }
        catch { /* toasts unavailable; the in-app badge still works */ }
    }

    public void Unregister()
    {
        if (!_registered) return;
        try { AppNotificationManager.Default.Unregister(); } catch { }
        _registered = false;
    }

    /// <summary>Show a toast for newly arrived notifications and flash the taskbar.</summary>
    public void NotifyNewActivity(int unreadCount, Window window)
    {
        if (unreadCount <= 0) return;
        ShowToast(unreadCount);
        FlashTaskbar(window);
    }

    private void ShowToast(int unreadCount)
    {
        if (!_registered) return;
        try
        {
            var body = unreadCount == 1 ? "新しい通知が1件あります" : $"新しい通知が{unreadCount}件あります";
            var notification = new AppNotificationBuilder()
                .AddText("YoruMimizuku")
                .AddText(body)
                .BuildNotification();
            AppNotificationManager.Default.Show(notification);
        }
        catch { /* ignore toast failures */ }
    }

    private static void FlashTaskbar(Window window)
    {
        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            var info = new FLASHWINFO
            {
                cbSize = (uint)Marshal.SizeOf<FLASHWINFO>(),
                hwnd = hwnd,
                dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG,
                uCount = uint.MaxValue,
                dwTimeout = 0
            };
            FlashWindowEx(ref info);
        }
        catch { /* flashing is best-effort */ }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FLASHWINFO
    {
        public uint cbSize;
        public IntPtr hwnd;
        public uint dwFlags;
        public uint uCount;
        public uint dwTimeout;
    }

    private const uint FLASHW_TRAY = 0x00000002;
    private const uint FLASHW_TIMERNOFG = 0x0000000C;

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
}

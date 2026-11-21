using System;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace YoruMimizuku.App.Services;

/// <summary>
/// The in-app confirmation pill (the Windows counterpart of the macOS ToastCenter):
/// one short message at a time that hides itself after a moment. A newer message
/// replaces the current one and restarts its timer. Each message belongs to the
/// window it was raised in, so <see cref="Views.ToastView"/> shows only its own
/// window's messages.
/// </summary>
public sealed class ToastCenter
{
    public static ToastCenter Shared { get; } = new();

    private static readonly TimeSpan DefaultDuration = TimeSpan.FromSeconds(1.8);

    private DispatcherQueueTimer? _timer;

    public string? Message { get; private set; }

    /// <summary>The window the current message was raised in.</summary>
    public XamlRoot? Origin { get; private set; }

    public event Action? MessageChanged;

    /// <summary>Must be called on the UI thread.</summary>
    public void Show(XamlRoot? origin, string message, TimeSpan? duration = null)
    {
        _timer?.Stop();
        Message = message;
        Origin = origin;
        MessageChanged?.Invoke();

        if (DispatcherQueue.GetForCurrentThread() is not { } queue) return;
        var timer = queue.CreateTimer();
        timer.Interval = duration ?? DefaultDuration;
        timer.IsRepeating = false;
        timer.Tick += (sender, _) =>
        {
            if (!ReferenceEquals(sender, _timer)) return;
            Dismiss();
        };
        _timer = timer;
        timer.Start();
    }

    public void Dismiss()
    {
        _timer?.Stop();
        _timer = null;
        Message = null;
        Origin = null;
        MessageChanged?.Invoke();
    }
}

using System;
using YoruMimizuku.App.Mvvm;
using YoruMimizuku.App.Services;

namespace YoruMimizuku.App.ViewModels;

public sealed class UpdateSettingsViewModel : ObservableObject
{
    public string CurrentVersion => UpdateService.Shared.VersionDisplay;
    public bool IsConfigured => UpdateService.Shared.IsConfigured;
    public string StatusText => IsConfigured
        ? $"更新フィード: {UpdateService.Shared.CurrentFeedUrl}"
        : "WinSparkle の公開鍵が未設定のため、Windows 更新チェックは無効です。";

    public bool AutomaticallyChecksForUpdates
    {
        get => AppSettings.Shared.AutomaticallyChecksForUpdates;
        set
        {
            if (AppSettings.Shared.AutomaticallyChecksForUpdates == value) return;
            AppSettings.Shared.AutomaticallyChecksForUpdates = value;
            OnPropertyChanged();
        }
    }

    public WindowsUpdateChannel Channel
    {
        get => AppSettings.Shared.UpdateChannel;
        set
        {
            if (AppSettings.Shared.UpdateChannel == value) return;
            AppSettings.Shared.UpdateChannel = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(StatusText));
        }
    }

    public int ChannelIndex
    {
        get => Channel == WindowsUpdateChannel.Stable ? 0 : 1;
        set => Channel = value == 1 ? WindowsUpdateChannel.Development : WindowsUpdateChannel.Stable;
    }

    public void CheckNow()
    {
        UpdateService.Shared.CheckForUpdates();
        OnPropertyChanged(nameof(IsConfigured));
        OnPropertyChanged(nameof(StatusText));
    }
}

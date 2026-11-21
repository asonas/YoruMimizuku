using System;
using System.ComponentModel;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using YoruMimizuku.App.Services;
using YoruMimizuku.App.ViewModels;
using DetailTab = YoruMimizuku.Core.DetailTab;

namespace YoruMimizuku.App.Views;

/// <summary>
/// A conversation in the detail pane: its thread, or its レコード tab, as the bar's
/// switch and レコードを表示 choose. The record is read the first time its tab shows.
/// </summary>
public sealed class ConversationPane : UserControl
{
    private readonly Grid _host = new();
    private readonly ConversationView _thread;
    private readonly ThreadViewModel _vm;
    private RecordView? _record;

    public ConversationPane(ThreadViewModel vm, WorkspaceViewModel workspace)
    {
        _vm = vm;
        _thread = new ConversationView(vm, workspace);
        _host.Children.Add(_thread);
        Content = _host;
        _ = _thread.LoadAsync();
    }

    public void Show(DetailTab tab)
    {
        if (tab == DetailTab.Record && _record is null)
        {
            _record = new RecordView(_vm);
            _host.Children.Add(_record);
        }
        _thread.Visibility = tab == DetailTab.Thread ? Visibility.Visible : Visibility.Collapsed;
        if (_record is not null) _record.Visibility = tab == DetailTab.Record ? Visibility.Visible : Visibility.Collapsed;
    }
}

/// <summary>
/// The prototype's レコード tab, as on macOS: who wrote the post and where it lives,
/// then the record exactly as stored in the author's repo
/// (<c>com.atproto.repo.getRecord</c>), indented with sorted keys. The handle and
/// label come from the thread, so they appear once it has loaded.
/// </summary>
public sealed class RecordView : UserControl
{
    private readonly ThreadViewModel _vm;
    private readonly Grid _rows = new() { ColumnSpacing = 12, RowSpacing = 6 };
    private readonly ContentControl _body = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch };

    public RecordView(ThreadViewModel vm)
    {
        _vm = vm;
        _rows.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _rows.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var stack = new StackPanel { Spacing = 14, Padding = new Thickness(24, 16, 24, 16) };
        stack.Children.Add(_rows);
        stack.Children.Add(_body);
        Content = new ScrollViewer { Content = stack };
        RenderRows();
        vm.PropertyChanged += OnThreadChanged;
        _ = LoadAsync();
    }

    private void OnThreadChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ThreadViewModel.Focused)) RenderRows();
    }

    private void RenderRows()
    {
        _rows.Children.Clear();
        _rows.RowDefinitions.Clear();
        var anchor = _vm.Focused;
        if (anchor is not null) AddRow("Handle", anchor.AuthorHandle);
        if (AtUri.Repo(_vm.Anchor) is { } did) AddRow("DID", did);
        AddRow("URI", _vm.Anchor);
        if (anchor?.MediaWarning is { } warning)
        {
            AddRow("Label", warning == "graphic" ? "閲覧注意（過激なメディア）" : "閲覧注意（センシティブ）");
        }
    }

    private void AddRow(string key, string value)
    {
        var row = _rows.RowDefinitions.Count;
        _rows.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var keyText = new TextBlock
        {
            Text = key,
            FontSize = 12.5,
            Foreground = Brush("AppTertiaryTextBrush"),
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        var valueText = new TextBlock
        {
            Text = value,
            FontSize = 12.5,
            FontFamily = new FontFamily("Consolas"),
            Foreground = Brush("AppTextBrush"),
            IsTextSelectionEnabled = true,
            TextWrapping = TextWrapping.Wrap,
        };
        Grid.SetRow(keyText, row);
        Grid.SetRow(valueText, row);
        Grid.SetColumn(valueText, 1);
        _rows.Children.Add(keyText);
        _rows.Children.Add(valueText);
    }

    private async Task LoadAsync()
    {
        _body.Content = new ProgressRing { IsActive = true, Width = 20, Height = 20, HorizontalAlignment = HorizontalAlignment.Left };
        try
        {
            var json = await _vm.Account.RecordLoadAsync(_vm.Anchor);
            _body.Content = new Border
            {
                Background = Brush("AppRowHoverBrush"),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12),
                Child = new TextBlock
                {
                    Text = json,
                    FontSize = 12,
                    FontFamily = new FontFamily("Consolas"),
                    Foreground = Brush("AppTextBrush"),
                    IsTextSelectionEnabled = true,
                    TextWrapping = TextWrapping.Wrap,
                },
            };
        }
        catch (Exception ex)
        {
            AppLog.Write("record load failed", ex);
            _body.Content = new TextBlock { Text = "レコードを読み込めませんでした", Foreground = Brush("AppSecondaryTextBrush") };
        }
    }

    private static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}

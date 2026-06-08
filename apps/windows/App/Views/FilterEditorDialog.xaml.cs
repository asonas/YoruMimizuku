using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class FilterEditorDialog : ContentDialog
{
    private sealed record KindOption(string Label, FilterTermKind Kind);
    private sealed record TermRow(ComboBox KindBox, TextBox ValueBox, Button RemoveButton, Guid Id);

    private static readonly KindOption[] KindOptions =
    [
        new("キーワード", FilterTermKind.Keyword),
        new("ユーザー", FilterTermKind.User),
        new("ハッシュタグ", FilterTermKind.Hashtag),
        new("メンション", FilterTermKind.Mention)
    ];

    private readonly SavedFilterModel? _editing;
    private readonly List<TermRow> _rows = new();

    public SavedFilterModel? Result { get; private set; }

    public FilterEditorDialog(SavedFilterModel? editing = null)
    {
        _editing = editing;
        InitializeComponent();
        Title = editing is null ? "フィルターを追加" : "フィルターを編集";
        NameBox.Text = editing?.Name ?? "";
        CombinatorBox.SelectedIndex = editing?.Combinator == FilterCombinator.Or ? 1 : 0;

        var terms = editing?.Terms.Count > 0
            ? editing.Terms
            : new List<FilterTermModel> { new() { Kind = FilterTermKind.Keyword, Value = "" } };
        foreach (var term in terms) AddTermRow(term);
        PrimaryButtonClick += OnPrimaryClick;
        UpdateCanSave();
    }

    private void OnAddTermClick(object sender, RoutedEventArgs e)
    {
        AddTermRow(new FilterTermModel { Kind = FilterTermKind.Keyword, Value = "" });
        UpdateCanSave();
    }

    private void AddTermRow(FilterTermModel term)
    {
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var kindBox = new ComboBox
        {
            ItemsSource = KindOptions,
            DisplayMemberPath = nameof(KindOption.Label),
            SelectedValuePath = nameof(KindOption.Kind),
            SelectedValue = term.Kind,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        kindBox.SelectionChanged += OnEditorChanged;

        var valueBox = new TextBox
        {
            Text = term.Value,
            PlaceholderText = Placeholder(term.Kind)
        };
        valueBox.TextChanged += OnEditorChanged;
        kindBox.SelectionChanged += (_, _) =>
        {
            if (kindBox.SelectedValue is FilterTermKind kind) valueBox.PlaceholderText = Placeholder(kind);
        };

        var remove = new Button
        {
            Content = new FontIcon { Glyph = "\uE711", FontSize = 11 },
            Padding = new Thickness(4),
            VerticalAlignment = VerticalAlignment.Center
        };

        Grid.SetColumn(kindBox, 0);
        Grid.SetColumn(valueBox, 1);
        Grid.SetColumn(remove, 2);
        grid.Children.Add(kindBox);
        grid.Children.Add(valueBox);
        grid.Children.Add(remove);
        TermsPanel.Children.Add(grid);

        var row = new TermRow(kindBox, valueBox, remove, term.Id);
        _rows.Add(row);
        remove.Click += (_, _) =>
        {
            if (_rows.Count <= 1) return;
            _rows.Remove(row);
            TermsPanel.Children.Remove(grid);
            UpdateCanSave();
        };
    }

    private void OnEditorChanged(object sender, object e) => UpdateCanSave();

    private void OnPrimaryClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        var terms = TermsFromRows().ToList();
        if (terms.Count == 0)
        {
            args.Cancel = true;
            ErrorText.Text = "条件を1つ以上入力してください。";
            ErrorText.Visibility = Visibility.Visible;
            return;
        }

        var name = NameBox.Text.Trim();
        Result = new SavedFilterModel
        {
            Id = _editing?.Id ?? Guid.NewGuid(),
            Name = name.Length == 0 ? Summary(terms, SelectedCombinator()) : name,
            Terms = terms,
            Combinator = SelectedCombinator(),
            CreatedAt = _editing?.CreatedAt ?? DateTimeOffset.UtcNow
        };
    }

    private void UpdateCanSave()
    {
        IsPrimaryButtonEnabled = TermsFromRows().Any();
        ErrorText.Visibility = Visibility.Collapsed;
        foreach (var row in _rows) row.RemoveButton.IsEnabled = _rows.Count > 1;
    }

    private IEnumerable<FilterTermModel> TermsFromRows()
    {
        foreach (var row in _rows)
        {
            var value = row.ValueBox.Text.Trim();
            if (value.Length == 0) continue;
            yield return new FilterTermModel
            {
                Id = row.Id,
                Kind = row.KindBox.SelectedValue is FilterTermKind kind ? kind : FilterTermKind.Keyword,
                Value = value
            };
        }
    }

    private FilterCombinator SelectedCombinator() =>
        (CombinatorBox.SelectedItem as ComboBoxItem)?.Tag as string == "or"
            ? FilterCombinator.Or
            : FilterCombinator.And;

    private static string Placeholder(FilterTermKind kind) => kind switch
    {
        FilterTermKind.User => "alice.bsky.social",
        FilterTermKind.Hashtag => "swift",
        FilterTermKind.Mention => "bob.bsky.social",
        _ => "キーワード"
    };

    private static string Summary(IReadOnlyList<FilterTermModel> terms, FilterCombinator combinator)
    {
        var fragments = terms.Select(t => t.Value.Trim()).Where(v => v.Length > 0);
        return combinator == FilterCombinator.Or ? "OR: " + string.Join(", ", fragments) : string.Join(" ", fragments);
    }
}

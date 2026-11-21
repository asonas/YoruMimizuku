using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;
using YoruMimizuku.App.Services;

namespace YoruMimizuku.App.ViewModels;

public enum WorkspaceTabKind { Home, Notifications, Filter }

public sealed class WorkspaceTab : ObservableObject
{
    public WorkspaceTabKind Kind { get; }
    public string Id { get; }
    public string Title { get; }
    public string? Subtitle { get; }
    public SavedFilterModel? Filter { get; }

    public WorkspaceTab(WorkspaceTabKind kind, string id, string title, string? subtitle = null,
        SavedFilterModel? filter = null)
    {
        Kind = kind; Id = id; Title = title; Subtitle = subtitle; Filter = filter;
    }
}

/// <summary>One page of the detail pane. The window builds <see cref="View"/> the
/// first time the page is shown and keeps it, so back / forward shows the page as
/// it was left.</summary>
public abstract class DetailPage
{
    /// <summary>The detail bar's title.</summary>
    public abstract string Title { get; }

    public Microsoft.UI.Xaml.UIElement? View { get; set; }
}

/// <summary>A conversation; <paramref name="title"/> is its anchor's author.</summary>
public sealed class ConversationPage(string anchorUri, string title) : DetailPage
{
    public string AnchorUri { get; } = anchorUri;
    public override string Title => title;
}

public sealed class AuthorPage(AuthorViewModel author) : DetailPage
{
    public AuthorViewModel Author { get; } = author;
    public override string Title => Author.HeaderName;
}

/// <summary>
/// The window's workspace: the sidebar's timelines (Home, Notifications and saved
/// filters, cycled with Ctrl+Shift+J/K) and the detail pane where conversations and
/// author pages open beside the selected timeline (ADR 0026). Mirrors the Swift
/// WorkspaceModel (filter CRUD, openHashtagFilter) and DetailPaneModel.
/// </summary>
public sealed class WorkspaceViewModel : ObservableObject
{
    public ObservableCollection<WorkspaceTab> Tabs { get; } = new();

    /// <summary>The detail pane's pages, with back / forward.</summary>
    public Core.DetailPaneModel<DetailPage> Detail { get; } = new();

    /// <summary>This window's account. Every account-scoped call made from this
    /// window goes through it, so another window's switch never redirects it.
    /// Set when the shell is entered; null while signed out.</summary>
    public IAccountClient? Account { get; set; }

    public string? AccountDid => Account?.Did;

    /// <summary>Raised when tabs or the selection change so the shell can rebuild
    /// the navigation pane and show the selected tab's content.</summary>
    public event Action? Changed;
    public event Action? FiltersChanged;

    private WorkspaceTab _selected;
    public WorkspaceTab Selected
    {
        get => _selected;
        set { if (SetProperty(ref _selected, value)) Changed?.Invoke(); }
    }

    public WorkspaceTab HomeTab { get; }
    public WorkspaceTab NotificationsTab { get; }

    public WorkspaceViewModel()
    {
        HomeTab = new WorkspaceTab(WorkspaceTabKind.Home, "home", "ホーム");
        NotificationsTab = new WorkspaceTab(WorkspaceTabKind.Notifications, "notifications", "通知");
        Tabs.Add(HomeTab);
        Tabs.Add(NotificationsTab);
        _selected = HomeTab;
    }

    public IReadOnlyList<SavedFilterModel> Filters => Tabs
        .Where(t => t.Kind == WorkspaceTabKind.Filter && t.Filter is not null)
        .Select(t => t.Filter!)
        .ToList();

    public void LoadFilters(IEnumerable<SavedFilterModel> filters)
    {
        foreach (var tab in Tabs.Where(t => t.Kind == WorkspaceTabKind.Filter).ToList())
        {
            Tabs.Remove(tab);
        }
        foreach (var filter in filters)
        {
            Tabs.Add(FilterTab(filter));
        }
        if (Selected.Kind == WorkspaceTabKind.Filter)
        {
            Selected = HomeTab;
        }
        Changed?.Invoke();
    }

    public void AddFilter(SavedFilterModel filter)
    {
        var tab = FilterTab(filter);
        Tabs.Add(tab);
        FiltersChanged?.Invoke();
        Selected = tab;
    }

    public void UpdateFilter(SavedFilterModel filter)
    {
        var existing = Tabs.FirstOrDefault(t => t.Kind == WorkspaceTabKind.Filter && t.Id == filter.Id.ToString());
        if (existing is null) return;
        var index = Tabs.IndexOf(existing);
        var replacement = FilterTab(filter);
        Tabs[index] = replacement;
        if (Selected == existing) Selected = replacement;
        FiltersChanged?.Invoke();
        Changed?.Invoke();
    }

    public void RemoveFilter(string id)
    {
        var tab = Tabs.FirstOrDefault(t => t.Kind == WorkspaceTabKind.Filter && t.Id == id);
        if (tab is null) return;
        var index = Tabs.IndexOf(tab);
        Tabs.Remove(tab);
        if (Selected == tab) Selected = Tabs[Math.Max(0, index - 1)];
        FiltersChanged?.Invoke();
        Changed?.Invoke();
    }

    /// <summary>Open the conversation around <paramref name="anchorUri"/> in the
    /// detail pane; <paramref name="title"/> is its author's name.</summary>
    public void OpenConversation(string anchorUri, string title)
    {
        Detail.Open(new Core.DetailEntry.Conversation(anchorUri), () => new ConversationPage(anchorUri, title));
    }

    public void OpenAuthor(PostItem post)
    {
        var actor = AtUri.Repo(post.Id);
        if (actor is null) return;
        OpenAuthor(actor, post.AuthorHandle, post.AuthorDisplayName, post.AvatarUrl);
    }

    /// <summary>Open a user's page in the detail pane. The tapped avatar's basics
    /// seed the header while the full profile loads.</summary>
    public void OpenAuthor(string actor, string handle, string displayName, string? avatarUrl)
    {
        Detail.Open(new Core.DetailEntry.Author(actor),
            () => new AuthorPage(new AuthorViewModel(actor, handle, displayName, avatarUrl)));
    }

    /// <summary>Create-or-select a hashtag filter tab (used when tapping a #tag in a post).</summary>
    public void OpenHashtagFilter(string tag)
    {
        var clean = tag.TrimStart('#').Trim();
        if (clean.Length == 0) return;
        var existing = Tabs.FirstOrDefault(t =>
            t.Kind == WorkspaceTabKind.Filter &&
            t.Filter is { } f && f.Terms.Count == 1 &&
            f.Terms[0].Kind == FilterTermKind.Hashtag &&
            string.Equals(f.Terms[0].Value.TrimStart('#'), clean, StringComparison.OrdinalIgnoreCase));
        if (existing is not null) { Selected = existing; return; }
        var filter = new SavedFilterModel
        {
            Name = "#" + clean,
            Terms = { new FilterTermModel { Kind = FilterTermKind.Hashtag, Value = clean } }
        };
        AddFilter(filter);
    }

    private static WorkspaceTab FilterTab(SavedFilterModel filter) =>
        new(WorkspaceTabKind.Filter, filter.Id.ToString(), filter.DisplayName, filter.Summary, filter: filter);

    public void SelectNextTab() => Cycle(1);
    public void SelectPreviousTab() => Cycle(-1);

    private void Cycle(int delta)
    {
        if (Tabs.Count == 0) return;
        var index = Tabs.IndexOf(Selected);
        var next = ((index + delta) % Tabs.Count + Tabs.Count) % Tabs.Count;
        Selected = Tabs[next];
    }
}

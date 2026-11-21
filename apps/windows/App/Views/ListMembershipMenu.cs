using System;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;
using YoruMimizuku.App.Services;
using YoruMimizuku.Core;

namespace YoruMimizuku.App.Views;

/// <summary>
/// The "リストに追加" submenu of a post row: the window account's curated lists with a
/// check on those the author is on, ending with a note that lists are public. A menu
/// shows the cache, which is read when the menu opens; until an author's membership is
/// read the lists are disabled under "所属を確認中…" rather than shown unchecked.
/// Choosing a list re-reads the server before writing. Port of the macOS
/// <c>ListMembershipMenu</c> (apps/macos/Views/ListMembershipMenu.swift).
/// </summary>
internal static class ListMembershipMenu
{
    /// <summary>
    /// Fill <paramref name="menu"/> for the author, and keep it current while the
    /// flyout is open, since the read started here usually answers after it opens.
    /// </summary>
    public static void Attach(MenuFlyout flyout, MenuFlyoutSubItem menu, ListMembershipModel model, string actorDid, string handle)
    {
        void Fill() => Populate(menu, model, actorDid, handle);
        void OnClosed(object? sender, object e)
        {
            model.Changed -= Fill;
            flyout.Closed -= OnClosed;
        }
        model.Changed += Fill;
        flyout.Closed += OnClosed;
        Fill();
        _ = model.RefreshIfStaleAsync(actorDid);
    }

    private static void Populate(MenuFlyoutSubItem menu, ListMembershipModel model, string actorDid, string handle)
    {
        menu.Items.Clear();
        if (model.Lists.Count == 0)
        {
            menu.Items.Add(Note(model.ListsState switch
            {
                ListsState.NotLoaded => "リストを読み込み中…",
                ListsState.Failed => "リストを読み込めませんでした",
                _ => "リストがありません",
            }));
        }
        if (model.Lists.Any(list => model.IsMember(actorDid, list.Id) is null))
        {
            menu.Items.Add(Note("所属を確認中…"));
        }
        foreach (var list in model.Lists)
        {
            var isMember = model.IsMember(actorDid, list.Id);
            var item = new ToggleMenuFlyoutItem
            {
                Text = list.Name,
                IsChecked = isMember == true,
                IsEnabled = isMember is not null,
            };
            // A click has already flipped IsChecked to the state asked for.
            item.Click += async (_, _) => await SetAsync(menu.XamlRoot, model, actorDid, handle, list, item.IsChecked);
            menu.Items.Add(item);
        }
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(Note("リストは公開され、誰でも見られます"));
    }

    private static MenuFlyoutItem Note(string text) => new() { Text = text, IsEnabled = false };

    private static async Task SetAsync(
        XamlRoot? origin, ListMembershipModel model, string actorDid, string handle, CuratedList list, bool member)
    {
        string message;
        try
        {
            var wrote = await model.SetMembershipAsync(actorDid, list.Id, member);
            message = (member, wrote) switch
            {
                (true, true) => $"@{handle} を「{list.Name}」に追加しました",
                (true, false) => $"@{handle} はすでに「{list.Name}」にいます",
                (false, true) => $"@{handle} を「{list.Name}」から外しました",
                (false, false) => $"@{handle} は「{list.Name}」にいません",
            };
        }
        catch (ListNotFoundException)
        {
            message = $"「{list.Name}」が見つかりませんでした";
        }
        catch (Exception ex)
        {
            AppLog.Write("list membership change failed", ex);
            message = "リストを更新できませんでした";
        }
        ToastCenter.Shared.Show(origin, message);
    }

    /// <summary>
    /// Add a dropped author to one of the window account's own pinned curated lists
    /// (the macOS sidebar's <c>addToList</c>).
    /// </summary>
    public static async Task AddDroppedAsync(XamlRoot? origin, ListMembershipModel model, DraggedAuthor author, string listUri, string title)
    {
        string message;
        try
        {
            message = await model.SetMembershipAsync(author.Did, listUri, true)
                ? $"@{author.Handle} を「{title}」に追加しました"
                : $"@{author.Handle} はすでに「{title}」にいます";
        }
        catch (Exception ex)
        {
            AppLog.Write("list drop failed", ex);
            message = "リストを更新できませんでした";
        }
        ToastCenter.Shared.Show(origin, message);
    }
}

/// <summary>
/// A post's author dragged by the avatar onto a sidebar list: the DID and handle under
/// the app's own format, and the <c>@handle</c> text for other apps (the macOS
/// <c>DraggedAuthor</c>).
/// </summary>
internal sealed record DraggedAuthor(string Did, string Handle)
{
    public const string Format = "as.ason.YoruMimizuku.author";

    public void WriteTo(DataPackage data)
    {
        data.SetData(Format, JsonSerializer.Serialize(this));
        data.SetText("@" + Handle);
        data.RequestedOperation = DataPackageOperation.Copy;
    }

    public static bool IsIn(DataPackageView view) => view.Contains(Format);

    public static async Task<DraggedAuthor?> ReadAsync(DataPackageView view) =>
        view.Contains(Format) && await view.GetDataAsync(Format) is string json
            ? JsonSerializer.Deserialize<DraggedAuthor>(json)
            : null;
}

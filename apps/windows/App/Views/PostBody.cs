using System;
using System.Collections.Generic;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

/// A post body as rich text: links open in the browser, hashtags open a filter,
/// and @mentions open the account in the detail pane, as on macOS.
internal static class PostBody
{
    public static void Fill(RichTextBlock rich, IReadOnlyList<RichSegmentDto> segments, WorkspaceViewModel workspace)
    {
        rich.Blocks.Clear();
        var paragraph = new Paragraph();
        foreach (var seg in segments)
        {
            switch (seg.Kind)
            {
                case "link" when TryUri(seg.Url, out var uri):
                    var link = new Hyperlink { NavigateUri = uri };
                    link.Inlines.Add(new Run { Text = seg.Text });
                    paragraph.Inlines.Add(link);
                    break;
                case "tag":
                    var tagLink = new Hyperlink();
                    tagLink.Inlines.Add(new Run { Text = seg.Text });
                    var tag = seg.Text.TrimStart('#');
                    tagLink.Click += (_, _) => workspace.OpenHashtagFilter(tag);
                    paragraph.Inlines.Add(tagLink);
                    break;
                case "mention" when TryUri(seg.Url, out var profileUri)
                                    && Core.RichText.MentionDid(profileUri) is { Length: > 0 } actor:
                    var mentionLink = new Hyperlink();
                    mentionLink.Inlines.Add(new Run { Text = seg.Text });
                    var handle = seg.Text.TrimStart('@');
                    mentionLink.Click += (_, _) => workspace.OpenAuthor(actor, handle, "", null);
                    paragraph.Inlines.Add(mentionLink);
                    break;
                case "mention":
                    paragraph.Inlines.Add(new Run
                    {
                        Text = seg.Text,
                        Foreground = (Brush)Application.Current.Resources["AppAccentBrush"]
                    });
                    break;
                default:
                    paragraph.Inlines.Add(new Run { Text = seg.Text });
                    break;
            }
        }
        rich.Blocks.Add(paragraph);
    }

    private static bool TryUri(string? value, out Uri uri)
    {
        if (!string.IsNullOrEmpty(value) && Uri.TryCreate(value, UriKind.Absolute, out var parsed))
        {
            uri = parsed;
            return true;
        }
        uri = null!;
        return false;
    }
}

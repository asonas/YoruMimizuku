using System.Threading.Tasks;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.Mvvm;

namespace YoruMimizuku.App.ViewModels;

public sealed class AuthorViewModel : ObservableObject
{
    public string Actor { get; }
    public string Handle { get; }
    public string DisplayName { get; }
    public string? AvatarUrl { get; }

    private ProfileDto? _profile;
    public ProfileDto? Profile { get => _profile; private set => SetProperty(ref _profile, value); }

    public string HeaderName => Profile?.DisplayName is { Length: > 0 } name ? name : DisplayName;
    public string HeaderHandle => "@" + (Profile?.Handle ?? Handle);
    public string? HeaderAvatarUrl => Profile?.AvatarUrl ?? AvatarUrl;
    public string? Bio => Profile?.Bio;

    public AuthorViewModel(string actor, string handle, string displayName, string? avatarUrl)
    {
        Actor = actor;
        Handle = handle;
        DisplayName = string.IsNullOrWhiteSpace(displayName) ? handle : displayName;
        AvatarUrl = avatarUrl;
    }

    /// <summary>The author's posts, read as <paramref name="account"/>. The tab
    /// outlives an account switch, so the feed is built for whichever account
    /// the window shows when the tab is displayed.</summary>
    public TimelineViewModel FeedFor(IAccountClient account) =>
        new(account, cursor => account.AuthorFeedLoadAsync(Actor, cursor));

    public async Task LoadProfileAsync(IAccountClient account)
    {
        try
        {
            Profile = await account.ProfileAsync(Actor);
            OnPropertyChanged(nameof(HeaderName));
            OnPropertyChanged(nameof(HeaderHandle));
            OnPropertyChanged(nameof(HeaderAvatarUrl));
            OnPropertyChanged(nameof(Bio));
        }
        catch
        {
            // The header is cosmetic; keep the tapped avatar snapshot on failure.
        }
    }
}

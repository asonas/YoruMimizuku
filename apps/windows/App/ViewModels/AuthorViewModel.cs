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
    public TimelineViewModel Feed { get; }

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
        Feed = new TimelineViewModel(cursor => BridgeClient.Shared.AuthorFeedLoadAsync(actor, cursor));
    }

    public async Task LoadProfileAsync()
    {
        try
        {
            Profile = await BridgeClient.Shared.ProfileAsync(Actor);
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

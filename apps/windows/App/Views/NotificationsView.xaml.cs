using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using YoruMimizuku.App.Interop;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class NotificationsView : UserControl
{
    public NotificationsViewModel Vm { get; }
    private readonly WorkspaceViewModel _workspace;

    public NotificationsView(WorkspaceViewModel workspace, NotificationsViewModel vm)
    {
        _workspace = workspace;
        Vm = vm;
        InitializeComponent();
    }

    public Task LoadAsync() => Vm.LoadAsync();

    private void OnActorAvatarTapped(object sender, TappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: NotificationGroupDto group } &&
            group.LeadActor is { } actor)
        {
            e.Handled = true;
            _workspace.OpenAuthor(actor.Handle, actor.Handle, actor.DisplayName, actor.AvatarUrl);
        }
    }
}

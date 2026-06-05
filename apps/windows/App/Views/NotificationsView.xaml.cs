using System.Threading.Tasks;
using Microsoft.UI.Xaml.Controls;
using YoruMimizuku.App.ViewModels;

namespace YoruMimizuku.App.Views;

public sealed partial class NotificationsView : UserControl
{
    public NotificationsViewModel Vm { get; } = new();

    public NotificationsView()
    {
        InitializeComponent();
    }

    public Task LoadAsync() => Vm.LoadAsync();
}

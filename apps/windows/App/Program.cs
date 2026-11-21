using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace YoruMimizuku.App;

/// <summary>
/// Replaces the XAML-generated Main (DISABLE_XAML_GENERATED_MAIN) so the app runs as
/// a single instance. Every process shares the account store, but refresh coalescing
/// and compare-and-save hold only inside one process, so a second process could write
/// back a used refresh token. A second launch hands its activation to the running
/// instance and exits before it touches the store.
/// </summary>
public static class Program
{
    [STAThread]
    private static int Main()
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        // The Windows App SDK scopes the key to this exe's path in the user's session.
        var instance = AppInstance.FindOrRegisterForKey("main");
        if (!instance.IsCurrent)
        {
            var args = AppInstance.GetCurrent().GetActivatedEventArgs();
            // Redirecting also passes this launch's foreground right to the running
            // instance. It runs on a pool thread, as the docs advise for an STA caller.
            Task.Run(() => instance.RedirectActivationToAsync(args).AsTask()).Wait();
            return 0;
        }
        Application.Start(_ =>
        {
            SynchronizationContext.SetSynchronizationContext(
                new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            var app = new App();
            instance.Activated += (_, _) => app.OnRedirectedLaunch();
        });
        return 0;
    }
}

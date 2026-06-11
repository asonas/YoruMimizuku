using System.Runtime.InteropServices;

namespace YoruMimizuku.App.Interop;

internal static class WinSparkleNative
{
    private const string Dll = "WinSparkle.dll";
    private const CallingConvention Conv = CallingConvention.Cdecl;

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern void win_sparkle_init();

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern void win_sparkle_cleanup();

    [DllImport(Dll, CallingConvention = Conv, CharSet = CharSet.Ansi)]
    internal static extern void win_sparkle_set_appcast_url(string url);

    [DllImport(Dll, CallingConvention = Conv, CharSet = CharSet.Unicode)]
    internal static extern void win_sparkle_set_app_details(string companyName, string appName, string appVersion);

    [DllImport(Dll, CallingConvention = Conv, CharSet = CharSet.Unicode)]
    internal static extern void win_sparkle_set_app_build_version(string build);

    [DllImport(Dll, CallingConvention = Conv, CharSet = CharSet.Ansi)]
    internal static extern void win_sparkle_set_registry_path(string path);

    [DllImport(Dll, CallingConvention = Conv, CharSet = CharSet.Ansi)]
    internal static extern int win_sparkle_set_eddsa_public_key(string pubkey);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern void win_sparkle_set_automatic_check_for_updates(int state);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern void win_sparkle_check_update_with_ui();
}

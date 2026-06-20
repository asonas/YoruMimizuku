using System;
using System.Runtime.InteropServices;

namespace YoruMimizuku.App.Interop;

/// <summary>
/// Raw P/Invoke surface for YoruMimizukuBridge.dll. Every entry point takes a
/// UTF-8 JSON request string and returns a newly-allocated UTF-8 JSON response
/// pointer that MUST be released with <see cref="yoru_free"/>. Use
/// <see cref="BridgeClient"/> rather than calling these directly.
/// </summary>
internal static class NativeMethods
{
    private const string Dll = "YoruMimizukuBridge.dll";
    private const CallingConvention Conv = CallingConvention.Cdecl;

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern void yoru_free(IntPtr ptr);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_init([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_account_current([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_account_list([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_account_switch([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_account_remove([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_account_summaries([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_account_remove_advance([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_login_begin([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_login_complete([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_timeline_load([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_author_feed_load([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_thread_load([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_notifications_load([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_search_load([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_post_create([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_post_like([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_post_unlike([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_post_repost([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_post_unrepost([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_post_permalink([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_post_delete([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_profile_avatar([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_profile_load([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_ogp_load([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    [DllImport(Dll, CallingConvention = Conv)]
    internal static extern IntPtr yoru_feed_arrange([MarshalAs(UnmanagedType.LPUTF8Str)] string input);

    /// <summary>Marshal the returned UTF-8 pointer to a managed string and free it.</summary>
    internal static string Consume(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero) return "{\"ok\":false,\"error\":\"null response\"}";
        try
        {
            return Marshal.PtrToStringUTF8(ptr) ?? "{\"ok\":false,\"error\":\"decode failed\"}";
        }
        finally
        {
            yoru_free(ptr);
        }
    }
}

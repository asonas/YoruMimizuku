using System;

namespace YoruMimizuku.App.Interop;

/// <summary>Thrown when a core operation fails. Carries the shared LoadFailure
/// classification (kind) and friendly title/message when present, so a view can
/// show a tailored failed state with a retry.</summary>
public sealed class BridgeException : Exception
{
    public string? Kind { get; }
    public string? Title { get; }
    public string? FriendlyMessage { get; }
    /// <summary>True when the stored session is no longer valid (invalid_grant on a
    /// refresh) and the app should drop it and return to login.</summary>
    public bool SessionExpired { get; }

    public BridgeException(string message, string? kind = null, string? title = null,
        string? friendlyMessage = null, bool sessionExpired = false)
        : base(message)
    {
        Kind = kind;
        Title = title;
        FriendlyMessage = friendlyMessage;
        SessionExpired = sessionExpired;
    }
}

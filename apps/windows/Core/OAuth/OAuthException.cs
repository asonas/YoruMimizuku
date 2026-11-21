namespace YoruMimizuku.Core.OAuth;

public enum OAuthErrorKind
{
    /// <summary>A discovery document answered with a non-success status.</summary>
    DiscoveryFailed,

    /// <summary>A document or response did not have the expected shape.</summary>
    MalformedDocument,

    PdsNotFound,
    UnsupportedDidMethod,
    ParNotSupported,
    AuthorizationRequestFailed,

    /// <summary>The user or the server refused the authorization at the callback.</summary>
    AuthorizationDenied,

    MissingAuthorizationCode,

    /// <summary>The callback's state is not the one this sign-in sent.</summary>
    StateMismatch,

    /// <summary>The callback's iss is missing or names another authorization server (RFC 9207).</summary>
    IssuerMismatch,

    /// <summary>The token endpoint refused the grant; <see cref="OAuthException.Error"/> holds its error code.</summary>
    TokenRequestFailed,

    /// <summary>The token's sub is not the DID that sign-in started for.</summary>
    SubjectMismatch,

    /// <summary>The token was granted without the atproto scope.</summary>
    MissingAtprotoScope,
}

/// <summary>
/// An OAuth failure. Messages name URLs, statuses and the server's error code, never
/// a token, a code or the DPoP key.
/// </summary>
public sealed class OAuthException : Exception
{
    internal OAuthException(OAuthErrorKind kind, string message, int? status = null, string? error = null)
        : base(message)
    {
        Kind = kind;
        Status = status;
        Error = error;
    }

    public OAuthErrorKind Kind { get; }

    /// <summary>The HTTP status of the failed response, when one came back.</summary>
    public int? Status { get; }

    /// <summary>The RFC 6749 error code the server sent, such as invalid_grant.</summary>
    public string? Error { get; }

    /// <summary>
    /// True when the refresh token is dead (invalid_grant): retrying cannot help, so the
    /// account has to sign in again.
    /// </summary>
    public bool IsSessionExpired => Kind == OAuthErrorKind.TokenRequestFailed && Error == "invalid_grant";

    internal static OAuthException Malformed(string detail) => new(OAuthErrorKind.MalformedDocument, $"Malformed OAuth document: {detail}");
}

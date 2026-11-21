namespace YoruMimizuku.Core.OAuth;

/// <summary>
/// The public OAuth client's identity. <see cref="YoruMimizuku"/> must match
/// docs/client-metadata.json, published at <see cref="ClientId"/>.
/// </summary>
public sealed record OAuthClientConfig(string ClientId, string RedirectUri, string Scope)
{
    public static OAuthClientConfig YoruMimizuku { get; } = new(
        "https://ason.as/yorumimizuku/client-metadata.json", "as.ason:/callback", "atproto transition:generic");

    /// <summary>The redirect URI's scheme, which marks the callback navigation in WebView2.</summary>
    public string CallbackScheme => RedirectUri.Split(':', 2)[0];
}

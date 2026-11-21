using System.Buffers.Text;
using System.Collections.Specialized;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Web;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Tests;

/// <summary>
/// An in-process identity directory, authorization server (auth.test) and PDS (pds.test)
/// that check what real ones check: signed DPoP proofs with fresh jti and the server's
/// nonce, PKCE, tokens bound to the key that proved them, and refresh tokens that work
/// once and rotate. A proof or grant it rejects fails the request, so the test fails.
/// </summary>
internal sealed class FakeAtproto : HttpMessageHandler
{
    public const string AliceDid = "did:plc:alice";
    public const string BobDid = "did:plc:bob";
    public const string WebDid = "did:web:web.test";
    public const string NoPdsDid = "did:plc:nopds";
    public const string Issuer = "https://auth.test";
    public static readonly Uri Pds = new("https://pds.test");
    private const string AuthNonce = "auth-nonce";
    private const string PdsNonce = "pds-nonce";

    private readonly object _gate = new();
    private readonly Dictionary<string, Authorization> _pars = [];
    private readonly Dictionary<string, Authorization> _codes = [];
    private readonly Dictionary<string, Grant> _refreshTokens = [];
    private readonly Dictionary<string, Grant> _accessTokens = [];
    private readonly HashSet<string> _jtis = [];
    private int _serial;
    private int _refreshCount;
    private int _nonceChallenges;

    /// <summary>The scope tokens are issued with; null leaves the field out.</summary>
    public string? Scope { get; set; } = "atproto transition:generic";

    public List<string> AuthorizationServers { get; } = [Issuer];

    public Action<JsonObject>? EditMetadata { get; set; }

    /// <summary>Runs before the fake's own routing; a response it returns is sent as is.</summary>
    public Func<ObservedRequest, Task<HttpResponseMessage?>>? Intercept { get; set; }

    /// <summary>Awaited at each refresh grant before the refresh token is checked.</summary>
    public Func<Task>? BeforeRefresh { get; set; }

    public int RefreshCount => Volatile.Read(ref _refreshCount);
    public int NonceChallenges => Volatile.Read(ref _nonceChallenges);
    public NameValueCollection? LastPar { get; private set; }
    public NameValueCollection? LastTokenRequest { get; private set; }

    public List<ObservedRequest> Requests
    {
        get { lock (_gate) return [.. _requests]; }
    }

    private readonly List<ObservedRequest> _requests = [];

    /// <summary>
    /// The browser half of sign-in: the user approves the request at the authorization
    /// endpoint as <paramref name="signedInAs"/>, and the server redirects to the callback.
    /// </summary>
    public string Approve(Uri authorizationUrl, string signedInAs = AliceDid, string? state = null, string? iss = Issuer)
    {
        var query = HttpUtility.ParseQueryString(authorizationUrl.Query);
        var code = "code-" + Interlocked.Increment(ref _serial);
        Authorization authorization;
        lock (_gate)
        {
            authorization = _pars[query["request_uri"]!];
            _codes[code] = authorization with { Did = signedInAs };
        }
        if (query["client_id"] != authorization.ClientId) throw new InvalidOperationException("client_id differs from the PAR.");
        var callback = $"{authorization.RedirectUri}?code={code}&state={Uri.EscapeDataString(state ?? authorization.State)}";
        return iss is null ? callback : callback + "&iss=" + Uri.EscapeDataString(iss);
    }

    /// <summary>Every access token issued so far stops working, as if it had expired.</summary>
    public void ExpireAccessTokens()
    {
        lock (_gate) _accessTokens.Clear();
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var sent = await ObservedRequest.CaptureAsync(request, cancellationToken);
        lock (_gate) _requests.Add(sent);
        if (Intercept is not null && await Intercept(sent) is { } custom) return custom;

        var path = sent.Uri.GetLeftPart(UriPartial.Path);
        var query = HttpUtility.ParseQueryString(sent.Uri.Query);
        return path switch
        {
            "https://bsky.social/xrpc/com.atproto.identity.resolveHandle" => ResolveHandle(query["handle"]),
            "https://plc.directory/" + AliceDid => DidDocument(AliceDid, withPds: true),
            "https://plc.directory/" + BobDid => DidDocument(BobDid, withPds: true),
            "https://plc.directory/" + NoPdsDid => DidDocument(NoPdsDid, withPds: false),
            "https://web.test/.well-known/did.json" => DidDocument(WebDid, withPds: true),
            "https://pds.test/.well-known/oauth-protected-resource" => Json(HttpStatusCode.OK, new JsonObject
            {
                ["resource"] = "https://pds.test",
                ["authorization_servers"] = new JsonArray([.. AuthorizationServers.Select(s => JsonValue.Create(s))]),
            }),
            Issuer + "/.well-known/oauth-authorization-server" => Metadata(),
            Issuer + "/oauth/par" => PushAuthorization(sent),
            Issuer + "/oauth/token" => await TokenAsync(sent),
            _ when path.StartsWith("https://pds.test/xrpc/", StringComparison.Ordinal) => Resource(sent),
            _ => new HttpResponseMessage(HttpStatusCode.NotFound),
        };
    }

    private static HttpResponseMessage ResolveHandle(string? handle) => handle switch
    {
        "alice.test" => Json(HttpStatusCode.OK, new JsonObject { ["did"] = AliceDid }),
        "bob.test" => Json(HttpStatusCode.OK, new JsonObject { ["did"] = BobDid }),
        _ => Json(HttpStatusCode.BadRequest, new JsonObject { ["error"] = "InvalidRequest", ["message"] = "Unable to resolve handle" }),
    };

    private static HttpResponseMessage DidDocument(string did, bool withPds)
    {
        var services = new JsonArray();
        if (withPds)
            services.Add(new JsonObject { ["id"] = "#atproto_pds", ["type"] = "AtprotoPersonalDataServer", ["serviceEndpoint"] = "https://pds.test" });
        return Json(HttpStatusCode.OK, new JsonObject { ["id"] = did, ["service"] = services });
    }

    private HttpResponseMessage Metadata()
    {
        var metadata = new JsonObject
        {
            ["issuer"] = Issuer,
            ["authorization_endpoint"] = Issuer + "/oauth/authorize",
            ["token_endpoint"] = Issuer + "/oauth/token",
            ["pushed_authorization_request_endpoint"] = Issuer + "/oauth/par",
            ["authorization_response_iss_parameter_supported"] = true,
        };
        EditMetadata?.Invoke(metadata);
        return Json(HttpStatusCode.OK, metadata);
    }

    private HttpResponseMessage PushAuthorization(ObservedRequest sent)
    {
        if (RejectProof(sent, AuthNonce, accessToken: null) is { } rejection) return rejection;
        var form = HttpUtility.ParseQueryString(sent.Body ?? "");
        LastPar = form;
        if (form["response_type"] != "code" || form["code_challenge_method"] != "S256")
            return OAuthError(HttpStatusCode.BadRequest, "invalid_request");

        var requestUri = "urn:ietf:params:oauth:request_uri:req-" + Interlocked.Increment(ref _serial);
        lock (_gate)
            _pars[requestUri] = new Authorization(
                form["client_id"]!, form["redirect_uri"]!, form["state"]!, form["code_challenge"]!, sent.Proof!.Thumbprint, Did: "");
        return Json(HttpStatusCode.Created, new JsonObject { ["request_uri"] = requestUri, ["expires_in"] = 60 }, AuthNonce);
    }

    private async Task<HttpResponseMessage> TokenAsync(ObservedRequest sent)
    {
        if (RejectProof(sent, AuthNonce, accessToken: null) is { } rejection) return rejection;
        var form = HttpUtility.ParseQueryString(sent.Body ?? "");
        LastTokenRequest = form;
        if (form["client_id"] != OAuthClientConfig.YoruMimizuku.ClientId) return OAuthError(HttpStatusCode.BadRequest, "invalid_client");
        var jkt = sent.Proof!.Thumbprint;

        if (form["grant_type"] == "authorization_code")
        {
            lock (_gate)
            {
                if (!_codes.Remove(form["code"] ?? "", out var authorization)) return OAuthError(HttpStatusCode.BadRequest, "invalid_grant");
                var challenge = Base64Url.EncodeToString(SHA256.HashData(Encoding.ASCII.GetBytes(form["code_verifier"] ?? "")));
                if (challenge != authorization.Challenge || form["redirect_uri"] != authorization.RedirectUri)
                    return OAuthError(HttpStatusCode.BadRequest, "invalid_grant");
                if (jkt != authorization.Jkt) return OAuthError(HttpStatusCode.BadRequest, "invalid_dpop_proof");
                return Issue(authorization.Did, jkt);
            }
        }

        if (form["grant_type"] != "refresh_token") return OAuthError(HttpStatusCode.BadRequest, "unsupported_grant_type");
        Interlocked.Increment(ref _refreshCount);
        if (BeforeRefresh is not null) await BeforeRefresh();
        lock (_gate)
        {
            if (!_refreshTokens.Remove(form["refresh_token"] ?? "", out var grant))
                return OAuthError(HttpStatusCode.BadRequest, "invalid_grant", "refresh token replayed or unknown");
            if (jkt != grant.Jkt) return OAuthError(HttpStatusCode.BadRequest, "invalid_dpop_proof");
            _accessTokens.Remove(grant.AccessToken);
            return Issue(grant.Did, jkt);
        }
    }

    private HttpResponseMessage Issue(string did, string jkt)
    {
        var serial = Interlocked.Increment(ref _serial);
        var grant = new Grant(did, jkt, $"at-{serial}", $"rt-{serial}");
        _accessTokens[grant.AccessToken] = grant;
        _refreshTokens[grant.RefreshToken] = grant;
        var body = new JsonObject
        {
            ["access_token"] = grant.AccessToken,
            ["token_type"] = "DPoP",
            ["refresh_token"] = grant.RefreshToken,
            ["expires_in"] = 300,
            ["sub"] = did,
        };
        if (Scope is not null) body["scope"] = Scope;
        return Json(HttpStatusCode.OK, body, AuthNonce);
    }

    private HttpResponseMessage Resource(ObservedRequest sent)
    {
        if (sent.Authorization is not { } authorization || !authorization.StartsWith("DPoP ", StringComparison.Ordinal))
            return Json(HttpStatusCode.Unauthorized, new JsonObject { ["error"] = "AuthMissing" });
        var accessToken = authorization["DPoP ".Length..];
        if (RejectProof(sent, PdsNonce, accessToken) is { } rejection) return rejection;

        Grant? grant;
        lock (_gate) _accessTokens.TryGetValue(accessToken, out grant);
        if (grant is null)
        {
            var expired = Json(HttpStatusCode.Unauthorized, new JsonObject { ["error"] = "invalid_token", ["message"] = "token expired" }, PdsNonce);
            expired.Headers.TryAddWithoutValidation("WWW-Authenticate", "DPoP error=\"invalid_token\"");
            return expired;
        }
        if (grant.Jkt != sent.Proof!.Thumbprint) return Json(HttpStatusCode.Unauthorized, new JsonObject { ["error"] = "invalid_dpop_proof" });
        return Json(HttpStatusCode.OK, new JsonObject { ["did"] = grant.Did, ["path"] = sent.Uri.AbsolutePath, ["body"] = sent.Body }, PdsNonce);
    }

    /// <summary>The server's rejection of the request's proof, or null when the proof is good.</summary>
    private HttpResponseMessage? RejectProof(ObservedRequest sent, string nonce, string? accessToken)
    {
        var proof = sent.Proof;
        var problem = proof switch
        {
            null => "missing DPoP proof",
            _ when proof.Header.GetProperty("typ").GetString() != "dpop+jwt" => "typ",
            _ when proof.Header.GetProperty("alg").GetString() != "ES256" => "alg",
            _ when !proof.SignatureValid => "signature",
            _ when proof.Claim("htm") != sent.Method.Method => "htm",
            _ when proof.Claim("htu") != sent.Uri.GetLeftPart(UriPartial.Path) => "htu",
            _ when Math.Abs(DateTimeOffset.UtcNow.ToUnixTimeSeconds() - long.Parse(proof.Claim("iat")!)) > 300 => "iat",
            _ when accessToken is not null && proof.Claim("ath") != Base64Url.EncodeToString(SHA256.HashData(Encoding.UTF8.GetBytes(accessToken))) => "ath",
            _ => null,
        };
        if (problem is null)
        {
            lock (_gate)
                if (!_jtis.Add(proof!.Claim("jti")!)) problem = "jti replayed";
        }
        if (problem is not null) return OAuthError(HttpStatusCode.BadRequest, "invalid_dpop_proof", problem);
        if (proof!.Claim("nonce") == nonce) return null;

        Interlocked.Increment(ref _nonceChallenges);
        var resourceServer = nonce == PdsNonce;
        var challenge = Json(
            resourceServer ? HttpStatusCode.Unauthorized : HttpStatusCode.BadRequest,
            new JsonObject { ["error"] = "use_dpop_nonce", ["error_description"] = "Authorization server requires nonce in DPoP proof" },
            nonce);
        if (resourceServer) challenge.Headers.TryAddWithoutValidation("WWW-Authenticate", "DPoP error=\"use_dpop_nonce\"");
        return challenge;
    }

    private static HttpResponseMessage OAuthError(HttpStatusCode status, string error, string? description = null)
    {
        var body = new JsonObject { ["error"] = error };
        if (description is not null) body["error_description"] = description;
        return Json(status, body);
    }

    private static HttpResponseMessage Json(HttpStatusCode status, JsonNode body, string? nonce = null)
    {
        var response = new HttpResponseMessage(status) { Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json") };
        if (nonce is not null) response.Headers.TryAddWithoutValidation("DPoP-Nonce", nonce);
        return response;
    }

    private sealed record Authorization(string ClientId, string RedirectUri, string State, string Challenge, string Jkt, string Did);

    private sealed record Grant(string Did, string Jkt, string AccessToken, string RefreshToken);
}

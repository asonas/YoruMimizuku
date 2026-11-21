using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core.OAuth;

/// <summary>
/// An account's P-256 DPoP key. The authorization server binds the account's tokens
/// to it at sign-in, so it is stored with the account and restored after a relaunch.
/// </summary>
internal sealed class DPoPKey
{
    private static readonly JsonSerializerOptions Compact = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    private readonly ECDsa _key;
    private readonly JsonObject _jwk;

    private DPoPKey(ECDsa key)
    {
        _key = key;
        var point = key.ExportParameters(includePrivateParameters: false).Q;
        _jwk = new JsonObject
        {
            ["kty"] = "EC",
            ["crv"] = "P-256",
            ["x"] = Base64Url.EncodeToString(point.X),
            ["y"] = Base64Url.EncodeToString(point.Y),
        };
    }

    public static DPoPKey Generate() => new(ECDsa.Create(ECCurve.NamedCurves.nistP256));

    public static DPoPKey FromPkcs8(byte[] pkcs8)
    {
        var key = ECDsa.Create();
        key.ImportPkcs8PrivateKey(pkcs8, out _);
        return new DPoPKey(key);
    }

    public byte[] ExportPkcs8() => _key.ExportPkcs8PrivateKey();

    /// <summary>
    /// An RFC 9449 proof for one request: htu is the URI without query and fragment, and
    /// <paramref name="accessToken"/>, when given, is bound through its SHA-256 (ath).
    /// </summary>
    public string CreateProof(HttpMethod method, Uri uri, string? accessToken, string? nonce)
    {
        var header = new JsonObject { ["typ"] = "dpop+jwt", ["alg"] = "ES256", ["jwk"] = _jwk.DeepClone() };
        var claims = new JsonObject
        {
            ["jti"] = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16)),
            ["htm"] = method.Method,
            ["htu"] = uri.GetLeftPart(UriPartial.Path),
            ["iat"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
        };
        if (nonce is not null) claims["nonce"] = nonce;
        if (accessToken is not null) claims["ath"] = Base64Url.EncodeToString(SHA256.HashData(Encoding.UTF8.GetBytes(accessToken)));

        var signingInput = Segment(header) + "." + Segment(claims);
        var signature = _key.SignData(
            Encoding.ASCII.GetBytes(signingInput), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        return signingInput + "." + Base64Url.EncodeToString(signature);
    }

    private static string Segment(JsonObject json) => Base64Url.EncodeToString(Encoding.UTF8.GetBytes(json.ToJsonString(Compact)));
}

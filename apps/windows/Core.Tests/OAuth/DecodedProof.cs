using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

/// <summary>
/// A DPoP proof JWT taken apart the way a server does: header and claims decoded,
/// the ES256 signature checked against the embedded JWK, and the key's RFC 7638
/// thumbprint, which servers bind tokens to.
/// </summary>
internal sealed class DecodedProof
{
    public required JsonElement Header { get; init; }
    public required JsonElement Claims { get; init; }
    public required bool SignatureValid { get; init; }
    public required string Thumbprint { get; init; }

    public string? Claim(string name) =>
        Claims.TryGetProperty(name, out var value) ? value.ToString() : null;

    public static DecodedProof Parse(string jwt)
    {
        var parts = jwt.Split('.');
        if (parts.Length != 3) throw new FormatException("A JWT has three segments.");
        var header = Segment(parts[0]);
        var jwk = header.GetProperty("jwk");
        var x = jwk.GetProperty("x").GetString()!;
        var y = jwk.GetProperty("y").GetString()!;

        using var publicKey = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = Base64Url.DecodeFromChars(x), Y = Base64Url.DecodeFromChars(y) },
        });
        var signed = Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]);
        var valid = publicKey.VerifyData(
            signed, Base64Url.DecodeFromChars(parts[2]), HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation);

        var canonicalJwk = $$"""{"crv":"P-256","kty":"EC","x":"{{x}}","y":"{{y}}"}""";
        return new DecodedProof
        {
            Header = header,
            Claims = Segment(parts[1]),
            SignatureValid = valid,
            Thumbprint = Base64Url.EncodeToString(SHA256.HashData(Encoding.UTF8.GetBytes(canonicalJwk))),
        };
    }

    private static JsonElement Segment(string segment)
    {
        using var document = JsonDocument.Parse(Base64Url.DecodeFromChars(segment));
        return document.RootElement.Clone();
    }
}

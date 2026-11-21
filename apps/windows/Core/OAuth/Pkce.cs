using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace YoruMimizuku.Core.OAuth;

/// <summary>An RFC 7636 S256 pair: the verifier stays here, the challenge goes in the PAR.</summary>
internal sealed record Pkce(string Verifier, string Challenge)
{
    /// <summary>A verifier of 32 random bytes, base64url: 43 characters.</summary>
    public static Pkce Generate() => FromVerifier(Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32)));

    public static Pkce FromVerifier(string verifier) =>
        new(verifier, Base64Url.EncodeToString(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))));

    public override string ToString() => "Pkce { redacted }";
}

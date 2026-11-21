using System.Buffers.Text;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Tests;

public class DPoPKeyTests
{
    [Fact]
    public void ProofCarriesTheHeaderAndClaimsAndVerifiesAgainstItsEmbeddedKey()
    {
        var key = DPoPKey.Generate();

        var proof = DecodedProof.Parse(key.CreateProof(
            HttpMethod.Get, new Uri("https://pds.test/xrpc/app.bsky.feed.getTimeline?limit=50#top"), accessToken: null, nonce: null));

        Assert.Equal("dpop+jwt", proof.Header.GetProperty("typ").GetString());
        Assert.Equal("ES256", proof.Header.GetProperty("alg").GetString());
        var jwk = proof.Header.GetProperty("jwk");
        Assert.Equal("EC", jwk.GetProperty("kty").GetString());
        Assert.Equal("P-256", jwk.GetProperty("crv").GetString());
        Assert.Equal(32, Base64Url.DecodeFromChars(jwk.GetProperty("x").GetString()).Length);
        Assert.Equal(32, Base64Url.DecodeFromChars(jwk.GetProperty("y").GetString()).Length);
        Assert.Equal("GET", proof.Claim("htm"));
        Assert.Equal("https://pds.test/xrpc/app.bsky.feed.getTimeline", proof.Claim("htu"));
        Assert.InRange(long.Parse(proof.Claim("iat")!), DateTimeOffset.UtcNow.AddMinutes(-1).ToUnixTimeSeconds(), DateTimeOffset.UtcNow.ToUnixTimeSeconds());
        Assert.Null(proof.Claim("ath"));
        Assert.Null(proof.Claim("nonce"));
        Assert.True(proof.SignatureValid);
    }

    [Fact]
    public void ProofBindsTheAccessTokenAndNonceAndHasAFreshJti()
    {
        var key = DPoPKey.Generate();
        var uri = new Uri("https://pds.test/xrpc/com.atproto.repo.createRecord");

        // Access token and ath from the example in RFC 9449 section 7.1.
        var proof = DecodedProof.Parse(key.CreateProof(HttpMethod.Post, uri, "Kz~8mXK1EalYznwH-LC-1fBAo.4Ljp~zsPE_NeO.gxU", "server-nonce"));
        var another = DecodedProof.Parse(key.CreateProof(HttpMethod.Post, uri, null, null));

        Assert.Equal("POST", proof.Claim("htm"));
        Assert.Equal("fUHyO2r2Z3DZ53EsNrWBb0xWXoaNy59IiKCAqksmQEo", proof.Claim("ath"));
        Assert.Equal("server-nonce", proof.Claim("nonce"));
        Assert.False(string.IsNullOrEmpty(proof.Claim("jti")));
        Assert.NotEqual(proof.Claim("jti"), another.Claim("jti"));
    }

    [Fact]
    public void AKeyRestoredFromItsExportSignsAsTheSameKey()
    {
        var key = DPoPKey.Generate();
        var uri = new Uri("https://pds.test/xrpc/x");

        var restored = DPoPKey.FromPkcs8(key.ExportPkcs8());

        var original = DecodedProof.Parse(key.CreateProof(HttpMethod.Get, uri, null, null));
        var again = DecodedProof.Parse(restored.CreateProof(HttpMethod.Get, uri, null, null));
        Assert.True(again.SignatureValid);
        Assert.Equal(original.Thumbprint, again.Thumbprint);
        Assert.NotEqual(original.Thumbprint, DecodedProof.Parse(DPoPKey.Generate().CreateProof(HttpMethod.Get, uri, null, null)).Thumbprint);
    }
}

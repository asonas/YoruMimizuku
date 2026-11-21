using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Tests;

public class PkceTests
{
    [Fact]
    public void ChallengeMatchesTheRfc7636TestVector()
    {
        var pkce = Pkce.FromVerifier("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk");

        Assert.Equal("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", pkce.Challenge);
    }

    [Fact]
    public void GeneratedVerifierIs43Base64UrlCharactersAndFreshEachTime()
    {
        var first = Pkce.Generate().Verifier;

        Assert.Equal(43, first.Length);
        Assert.Matches("^[A-Za-z0-9_-]+$", first);
        Assert.NotEqual(first, Pkce.Generate().Verifier);
    }
}

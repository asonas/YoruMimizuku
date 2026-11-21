using System.Text.Json;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Tests;

public class OAuthClientConfigTests
{
    [Fact]
    public void ProductionConfigMatchesThePublishedClientMetadata()
    {
        using var metadata = JsonDocument.Parse(File.ReadAllText(ClientMetadataPath()));
        var root = metadata.RootElement;
        var config = OAuthClientConfig.YoruMimizuku;

        Assert.Equal(root.GetProperty("client_id").GetString(), config.ClientId);
        Assert.Equal(root.GetProperty("redirect_uris")[0].GetString(), config.RedirectUri);
        Assert.Equal(root.GetProperty("scope").GetString(), config.Scope);
    }

    [Theory]
    [InlineData("as.ason:/callback", "as.ason")]
    [InlineData("myapp:/cb", "myapp")]
    public void CallbackSchemeIsTheRedirectUriScheme(string redirectUri, string scheme)
    {
        Assert.Equal(scheme, new OAuthClientConfig("x", redirectUri, "s").CallbackScheme);
    }

    private static string ClientMetadataPath()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "docs", "client-metadata.json");
            if (File.Exists(candidate)) return candidate;
        }
        throw new FileNotFoundException("docs/client-metadata.json not found above the test output.");
    }
}

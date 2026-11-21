using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.App.Interop.Tests;

/// <summary>
/// Compares a DTO with the JSON the Swift bridge encodes for the same input: camelCase
/// keys, and an absent key for a nil optional, as Swift's JSONEncoder writes them.
/// </summary>
internal static class BridgeJson
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    public static void Equal(string expected, object actual)
    {
        var written = JsonSerializer.SerializeToNode(actual, actual.GetType(), Options);
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(expected), written), written?.ToJsonString());
    }
}

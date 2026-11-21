using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class RecordResponseTests
{
    /// `com.atproto.repo.getRecord` returns the record as stored; the record tab
    /// shows it verbatim, pretty-printed with sorted keys.
    [Fact]
    public void AnyRecordValueRoundTripsToPrettyJson()
    {
        var body = """
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/3k",
          "cid": "bafy",
          "value": {
            "text": "hi",
            "$type": "app.bsky.feed.post",
            "langs": ["ja"],
            "createdAt": "2026-11-20T03:10:00.000Z",
            "embed": { "$type": "app.bsky.embed.images", "images": [{ "alt": "", "aspectRatio": { "width": 1600, "height": 1000 } }] },
            "reply": null,
            "labels": false,
            "score": 1.5
          }
        }
        """;

        var response = RecordResponse.FromJson(JsonElement.Parse(body));

        Assert.Equal("at://did:plc:alice/app.bsky.feed.post/3k", response.Uri);
        var expected = """
        {
          "$type": "app.bsky.feed.post",
          "createdAt": "2026-11-20T03:10:00.000Z",
          "embed": {
            "$type": "app.bsky.embed.images",
            "images": [
              {
                "alt": "",
                "aspectRatio": {
                  "height": 1000,
                  "width": 1600
                }
              }
            ]
          },
          "labels": false,
          "langs": [
            "ja"
          ],
          "reply": null,
          "score": 1.5,
          "text": "hi"
        }
        """;
        // The source file's line endings depend on the checkout; the output uses \n.
        Assert.Equal(expected.ReplaceLineEndings("\n"), response.PrettyValue);
    }

    /// Integers beyond a Double's 53-bit precision come back exactly as stored.
    [Fact]
    public void LargeIntegersKeepTheirExactValue()
    {
        var response = RecordResponse.FromJson(
            JsonElement.Parse("""{"uri":"at://a/b/c","value":{"n":9007199254740993}}"""));

        Assert.Contains("9007199254740993", response.PrettyValue);
    }

    /// Verbatim means Japanese text and URLs are not turned into escape sequences.
    [Fact]
    public void TextIsNotEscaped()
    {
        var response = RecordResponse.FromJson(
            JsonElement.Parse("""{"uri":"at://a/b/c","value":{"text":"こんにちは https://example.com/a"}}"""));

        Assert.Contains("\"text\": \"こんにちは https://example.com/a\"", response.PrettyValue);
    }
}

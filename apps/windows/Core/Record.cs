using System.Buffers;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace YoruMimizuku.Core;

/// <summary><c>com.atproto.repo.getRecord</c>: one record as stored in its repo.</summary>
public sealed record RecordResponse(string Uri, string? Cid, JsonElement Value)
{
    public static RecordResponse FromJson(JsonElement json) =>
        new(json.RequiredString("uri"), json.OptionalString("cid"), json.Required("value").Clone());

    /// <summary>
    /// The record indented with keys sorted, for reading it as written: numbers keep
    /// their exact digits and text is not escaped beyond what JSON requires.
    /// </summary>
    public string PrettyValue
    {
        get
        {
            var buffer = new ArrayBufferWriter<byte>();
            var options = new JsonWriterOptions
            {
                Indented = true,
                NewLine = "\n",
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            };
            using (var writer = new Utf8JsonWriter(buffer, options))
            {
                WriteSorted(writer, Value);
            }
            return Encoding.UTF8.GetString(buffer.WrittenSpan);
        }
    }

    private static void WriteSorted(Utf8JsonWriter writer, JsonElement value)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
                writer.WriteStartObject();
                foreach (var property in value.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(property.Name);
                    WriteSorted(writer, property.Value);
                }
                writer.WriteEndObject();
                break;
            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (var item in value.EnumerateArray()) WriteSorted(writer, item);
                writer.WriteEndArray();
                break;
            default:
                value.WriteTo(writer);
                break;
        }
    }
}

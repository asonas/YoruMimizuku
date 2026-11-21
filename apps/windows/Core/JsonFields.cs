using System.Text.Json;

namespace YoruMimizuku.Core;

/// <summary>
/// Field readers for parsing XRPC JSON into models. A missing required field or a
/// field of the wrong JSON type throws <see cref="JsonException"/>; a JSON null reads
/// as absent. <see cref="Tolerant{T}"/> turns such a failure into null where a model
/// must survive a shape it does not render.
/// </summary>
internal static class JsonFields
{
    public static JsonElement? Optional(this JsonElement json, string name)
    {
        if (json.ValueKind != JsonValueKind.Object)
            throw new JsonException($"Expected an object holding '{name}', got {json.ValueKind}.");
        return json.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null ? value : null;
    }

    public static JsonElement Required(this JsonElement json, string name) =>
        json.Optional(name) ?? throw new JsonException($"Missing '{name}'.");

    public static string RequiredString(this JsonElement json, string name) =>
        AsString(json.Required(name), name);

    public static string? OptionalString(this JsonElement json, string name) =>
        json.Optional(name) is { } value ? AsString(value, name) : null;

    public static int RequiredInt(this JsonElement json, string name) =>
        AsInt(json.Required(name), name);

    public static int? OptionalInt(this JsonElement json, string name) =>
        json.Optional(name) is { } value ? AsInt(value, name) : null;

    public static bool? OptionalBool(this JsonElement json, string name) =>
        json.Optional(name) switch
        {
            null => null,
            { ValueKind: JsonValueKind.True } => true,
            { ValueKind: JsonValueKind.False } => false,
            var value => throw new JsonException($"'{name}' is {value.Value.ValueKind}, not a boolean."),
        };

    public static IReadOnlyList<T> RequiredArray<T>(this JsonElement json, string name, Func<JsonElement, T> parse) =>
        AsArray(json.Required(name), name).Select(parse).ToList();

    /// <summary>The parsed array, or null when absent. One bad element fails the whole array.</summary>
    public static IReadOnlyList<T>? OptionalArray<T>(this JsonElement json, string name, Func<JsonElement, T> parse) =>
        json.Optional(name) is { } value ? AsArray(value, name).Select(parse).ToList() : null;

    /// <summary>The elements that parse, in order; empty when the field is absent or not an array.</summary>
    public static IReadOnlyList<T> ArrayDroppingInvalid<T>(this JsonElement json, string name, Func<JsonElement, T> parse)
        where T : class =>
        json.Optional(name) is { ValueKind: JsonValueKind.Array } value
            ? value.EnumerateArray().Select(element => Tolerant(() => parse(element))).OfType<T>().ToList()
            : [];

    /// <summary>The parsed value, or null when the JSON does not have the expected shape.</summary>
    public static T? Tolerant<T>(Func<T?> parse) where T : class
    {
        try
        {
            return parse();
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string AsString(JsonElement value, string name) =>
        value.ValueKind == JsonValueKind.String
            ? value.GetString()!
            : throw new JsonException($"'{name}' is {value.ValueKind}, not a string.");

    private static int AsInt(JsonElement value, string name) =>
        value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)
            ? number
            : throw new JsonException($"'{name}' is not a 32-bit integer.");

    private static JsonElement.ArrayEnumerator AsArray(JsonElement value, string name) =>
        value.ValueKind == JsonValueKind.Array
            ? value.EnumerateArray()
            : throw new JsonException($"'{name}' is {value.ValueKind}, not an array.");
}

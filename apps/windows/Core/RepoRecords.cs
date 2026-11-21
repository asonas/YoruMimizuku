using System.Globalization;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core;

/// <summary>Writing records to the account's own repo (<c>com.atproto.repo.*</c>).</summary>
internal static class RepoRecords
{
    public static Task<StrongRef> CreateRecordAsync(
        this XrpcClient xrpc, string collection, JsonObject record, CancellationToken cancellationToken) =>
        xrpc.ProcedureAsync(
            "com.atproto.repo.createRecord",
            XrpcClient.Json(new JsonObject { ["repo"] = xrpc.Did, ["collection"] = collection, ["record"] = record }),
            json => new StrongRef(json.RequiredString("uri"), json.RequiredString("cid")),
            cancellationToken);

    public static Task DeleteRecordAsync(
        this XrpcClient xrpc, string collection, string recordUri, CancellationToken cancellationToken)
    {
        var address = AtUri.Parse(recordUri)
            ?? throw new ArgumentException($"Not a record URI: {recordUri}", nameof(recordUri));
        return xrpc.ProcedureAsync(
            "com.atproto.repo.deleteRecord",
            XrpcClient.Json(new JsonObject { ["repo"] = xrpc.Did, ["collection"] = collection, ["rkey"] = address.Rkey }),
            cancellationToken);
    }

    /// <summary>The current time as atproto records write it: UTC with milliseconds.</summary>
    public static string Timestamp(TimeProvider? clock) =>
        (clock ?? TimeProvider.System).GetUtcNow().UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
}

namespace YoruMimizuku.App.Services;

public static class AtUri
{
    public static string? Repo(string uri)
    {
        const string prefix = "at://";
        if (!uri.StartsWith(prefix)) return null;
        var parts = uri[prefix.Length..].Split('/');
        return parts.Length == 3 && parts[0].Length > 0 ? parts[0] : null;
    }
}

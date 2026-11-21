using System.Net;

namespace YoruMimizuku.Core;

public enum LoadFailureKind
{
    /// <summary>The network could not be reached: no route, DNS failure, dropped connection or timeout.</summary>
    Offline,

    /// <summary>The server asked us to slow down (HTTP 429).</summary>
    RateLimited,

    /// <summary>The server failed (HTTP 5xx).</summary>
    Server,

    /// <summary>Anything else: decoding, a 4xx other than 429, the unexpected.</summary>
    Unknown,
}

/// <summary>
/// A failed load, classified for the error screen: a friendly title and message by
/// kind, plus <paramref name="Detail"/>, the raw error for a small debug line.
/// </summary>
public sealed record LoadFailure(LoadFailureKind Kind, string Detail)
{
    /// <summary>
    /// Classifies what <see cref="HttpClient"/> throws. An HTTP status counts only when
    /// it arrives on an <see cref="HttpRequestException"/>, as from
    /// <see cref="HttpResponseMessage.EnsureSuccessStatusCode"/>; an HttpClient timeout
    /// arrives as a <see cref="TaskCanceledException"/> around a <see cref="TimeoutException"/>.
    /// </summary>
    public static LoadFailure From(Exception error) =>
        new(Classify(error), $"{error.GetType().Name}: {error.Message}");

    private static LoadFailureKind Classify(Exception error) => error switch
    {
        HttpRequestException { StatusCode: HttpStatusCode.TooManyRequests } => LoadFailureKind.RateLimited,
        HttpRequestException { StatusCode: >= HttpStatusCode.InternalServerError and <= (HttpStatusCode)599 } =>
            LoadFailureKind.Server,
        HttpRequestException
        {
            HttpRequestError: HttpRequestError.NameResolutionError
                or HttpRequestError.ConnectionError
                or HttpRequestError.ResponseEnded,
        } => LoadFailureKind.Offline,
        TaskCanceledException { InnerException: TimeoutException } => LoadFailureKind.Offline,
        _ => LoadFailureKind.Unknown,
    };

    /// <summary>A short headline for the error screen.</summary>
    public string Title => Kind switch
    {
        LoadFailureKind.Offline => "オフラインのようです",
        LoadFailureKind.RateLimited => "リクエストが多すぎます",
        LoadFailureKind.Server => "サーバーエラー",
        _ => "読み込みに失敗しました",
    };

    /// <summary>One line on what happened and what to try next.</summary>
    public string Message => Kind switch
    {
        LoadFailureKind.Offline => "インターネット接続を確認して、もう一度お試しください。",
        LoadFailureKind.RateLimited => "しばらく時間をおいてから再試行してください。",
        LoadFailureKind.Server => "サーバー側で問題が発生しました。時間をおいて再試行してください。",
        _ => "通信中に問題が発生しました。再試行してください。",
    };
}

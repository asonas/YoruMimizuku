namespace YoruMimizuku.Core;

/// <summary>
/// Where a post row places its media: <see cref="Vertical"/> stacks it under the body;
/// <see cref="Reflow"/> puts the body on the left and the media in a fixed-width rail
/// on the right.
/// </summary>
public enum TimelineMediaPlacement
{
    Vertical,
    Reflow,
}

/// <summary>The timeline row's layout math, as the Swift TimelineLayout defines it.</summary>
public static class TimelineLayout
{
    /// <summary>The body-and-media width from which the row reflows: text 360 + gap 16 + rail 300, rounded.</summary>
    public const double ReflowThreshold = 680;

    public const double MediaRailWidth = 300;

    public const double ColumnGap = 16;

    /// <summary>The lowest single-image width/height ratio shown uncropped: 5:4.</summary>
    public const double MinSingleImageRatio = 0.8;

    /// <summary>The highest single-image ratio (the panorama clamp).</summary>
    public const double MaxSingleImageRatio = 5.0;

    /// <summary>The ratio assumed for an image whose embed reports none.</summary>
    public const double DefaultImageRatio = 4.0 / 3.0;

    public static TimelineMediaPlacement Placement(double regionWidth) =>
        regionWidth >= ReflowThreshold ? TimelineMediaPlacement.Reflow : TimelineMediaPlacement.Vertical;

    public static double ClampedSingleImageRatio(double natural) =>
        Math.Clamp(natural, MinSingleImageRatio, MaxSingleImageRatio);

    /// <summary>Whether a single image is cut to 5:4, so the row shows the "全体表示" hint.</summary>
    public static bool IsTallCropped(double natural) => natural < MinSingleImageRatio;

    /// <summary>The display height of a single image <paramref name="width"/> wide.</summary>
    public static double SingleImageHeight(double width, double? aspectRatio) =>
        width / ClampedSingleImageRatio(aspectRatio is > 0 ? aspectRatio.Value : DefaultImageRatio);
}

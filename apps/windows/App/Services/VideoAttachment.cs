using System;
using System.IO;
using System.Threading.Tasks;
using Windows.Storage;
using Windows.Storage.FileProperties;

namespace YoruMimizuku.App.Services;

/// <summary>
/// A video file picked for the composer: its bytes as-is (Windows does not transcode,
/// as macOS does not) and its display size, read from the file's video properties.
/// </summary>
public sealed record VideoAttachment(byte[] Data, string MimeType, string Filename, int? Width, int? Height)
{
    public static async Task<VideoAttachment> LoadAsync(StorageFile file)
    {
        var data = await File.ReadAllBytesAsync(file.Path);
        // The picker offers .mp4, .m4v and .mov.
        var mimeType = file.FileType.Equals(".mov", StringComparison.OrdinalIgnoreCase) ? "video/quicktime" : "video/mp4";
        var (width, height) = await DisplaySizeAsync(file);
        return new VideoAttachment(data, mimeType, file.Name, width, height);
    }

    /// <summary>
    /// The size the video plays at: the encoded size, turned for a clip recorded
    /// sideways. Unknown (null) when the file reports none; the post is still valid,
    /// only without an aspect ratio.
    /// </summary>
    private static async Task<(int?, int?)> DisplaySizeAsync(StorageFile file)
    {
        try
        {
            var properties = await file.Properties.GetVideoPropertiesAsync();
            if (properties.Width == 0 || properties.Height == 0) return (null, null);
            var sideways = properties.Orientation is VideoOrientation.Rotate90 or VideoOrientation.Rotate270;
            return sideways
                ? ((int)properties.Height, (int)properties.Width)
                : ((int)properties.Width, (int)properties.Height);
        }
        catch (Exception)
        {
            return (null, null);
        }
    }
}

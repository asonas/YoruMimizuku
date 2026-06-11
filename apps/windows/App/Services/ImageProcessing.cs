using System;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Tasks;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace YoruMimizuku.App.Services;

/// <summary>
/// Downsamples and re-encodes attachment images before upload, the Windows
/// analogue of the macOS/iPadOS JPEG re-encode. Bluesky rejects very large
/// blobs, so an oversized image is scaled so its longest edge fits
/// <see cref="MaxEdge"/> and re-encoded as JPEG. Any failure falls back to the
/// original bytes so attaching never breaks on an odd codec.
/// </summary>
public static class ImageProcessing
{
    public const uint MaxEdge = 2000;

    public static async Task<(byte[] Data, string MimeType)> PrepareAsync(byte[] input, string mimeType)
    {
        try
        {
            using var inStream = new InMemoryRandomAccessStream();
            await inStream.WriteAsync(input.AsBuffer());
            inStream.Seek(0);

            var decoder = await BitmapDecoder.CreateAsync(inStream);
            var width = decoder.PixelWidth;
            var height = decoder.PixelHeight;
            var longest = Math.Max(width, height);

            // Already within bounds and already JPEG: leave it untouched.
            if (longest <= MaxEdge && mimeType == "image/jpeg") return (input, mimeType);

            using var softwareBitmap = await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);

            using var outStream = new InMemoryRandomAccessStream();
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, outStream);
            encoder.SetSoftwareBitmap(softwareBitmap);
            if (longest > MaxEdge)
            {
                var scale = (double)MaxEdge / longest;
                encoder.BitmapTransform.ScaledWidth = (uint)Math.Round(width * scale);
                encoder.BitmapTransform.ScaledHeight = (uint)Math.Round(height * scale);
                encoder.BitmapTransform.InterpolationMode = BitmapInterpolationMode.Fant;
            }
            await encoder.FlushAsync();

            outStream.Seek(0);
            var bytes = new byte[outStream.Size];
            await outStream.ReadAsync(bytes.AsBuffer(), (uint)outStream.Size, InputStreamOptions.None);
            return (bytes, "image/jpeg");
        }
        catch
        {
            return (input, mimeType);
        }
    }
}

using System.Collections.Generic;
using System.Linq;

namespace YoruMimizuku.App.ViewModels;

public static class UnreadCounter
{
    public static int Count(IEnumerable<string> ids, string? marker)
    {
        if (marker is null) return 0;
        var list = ids.ToList();
        var index = list.IndexOf(marker);
        return index < 0 ? list.Count : index;
    }
}

namespace YoruMimizuku.Core.Tests;

public class PostTextTests
{
    [Fact]
    public void RemovesTrailingNewlines()
    {
        Assert.Equal("hello", PostText.TrimTrailingWhitespace("hello\n\n"));
    }

    [Fact]
    public void PreservesInteriorBreaksWhileDroppingTrailingBlankLines()
    {
        Assert.Equal("line1\n\nline2", PostText.TrimTrailingWhitespace("line1\n\nline2\n \n"));
    }

    [Fact]
    public void RemovesTrailingSpacesAndTabs()
    {
        Assert.Equal("hi", PostText.TrimTrailingWhitespace("hi \t "));
    }

    [Fact]
    public void AllWhitespaceBecomesEmpty()
    {
        Assert.Equal("", PostText.TrimTrailingWhitespace("  \n\t\n"));
    }

    [Fact]
    public void TextWithoutTrailingWhitespaceIsUnchanged()
    {
        Assert.Equal("no trailing", PostText.TrimTrailingWhitespace("no trailing"));
    }
}

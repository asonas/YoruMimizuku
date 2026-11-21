namespace YoruMimizuku.Core.Tests;

/// <summary>The same cases as the Swift TimelineLayoutTests.</summary>
public class TimelineLayoutTests
{
    [Fact]
    public void ReflowsFromSixHundredEightyWide()
    {
        Assert.Equal(TimelineMediaPlacement.Vertical, TimelineLayout.Placement(679));
        Assert.Equal(TimelineMediaPlacement.Reflow, TimelineLayout.Placement(680));
    }

    [Fact]
    public void SingleImageRatioIsCappedAtFiveToFourAndFiveToOne()
    {
        Assert.Equal(0.8, TimelineLayout.ClampedSingleImageRatio(0.5));
        Assert.Equal(1.5, TimelineLayout.ClampedSingleImageRatio(1.5));
        Assert.Equal(5.0, TimelineLayout.ClampedSingleImageRatio(8.0));
    }

    [Fact]
    public void OnlyImagesTallerThanFiveToFourAreCropped()
    {
        Assert.True(TimelineLayout.IsTallCropped(0.5));
        Assert.False(TimelineLayout.IsTallCropped(0.8));
        Assert.False(TimelineLayout.IsTallCropped(1.5));
    }

    [Fact]
    public void SingleImageHeightFollowsTheClampedRatioAndDefaultsToFourToThree()
    {
        Assert.Equal(375, TimelineLayout.SingleImageHeight(300, 0.5));
        Assert.Equal(150, TimelineLayout.SingleImageHeight(300, 2.0));
        Assert.Equal(225, TimelineLayout.SingleImageHeight(300, null));
    }
}

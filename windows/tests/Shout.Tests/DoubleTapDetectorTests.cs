using Shout.Core;
using Xunit;

namespace Shout.Tests;

public class DoubleTapDetectorTests
{
    [Fact]
    public void ZweiSchnelleAnschlaegeStarten()
    {
        var detector = new DoubleTapDetector();
        Assert.Equal(DoubleTapDetector.Action.Armed, detector.HandleDown(0, isRecording: false));
        Assert.Equal(DoubleTapDetector.Action.Start, detector.HandleDown(0.3, isRecording: false));
    }

    [Fact]
    public void ZuLangsamZaehltAlsNeuerErsterTipp()
    {
        var detector = new DoubleTapDetector();
        detector.HandleDown(0, isRecording: false);
        Assert.Equal(DoubleTapDetector.Action.Armed, detector.HandleDown(1.5, isRecording: false));
        Assert.Equal(DoubleTapDetector.Action.Start, detector.HandleDown(1.9, isRecording: false));
    }

    [Fact]
    public void EinTippStopptDieLaufendeAufnahme()
    {
        var detector = new DoubleTapDetector();
        detector.HandleDown(0, isRecording: false);
        detector.HandleDown(0.3, isRecording: false);
        Assert.Equal(DoubleTapDetector.Action.Stop, detector.HandleDown(5, isRecording: true));
    }

    /// <summary>Der Grund für die Sperrfrist: Ein versehentlicher dritter schneller
    /// Tipp soll die gerade begonnene Aufnahme nicht sofort wieder beenden.</summary>
    [Fact]
    public void DritterTippInnerhalbDerSperrfristWirdIgnoriert()
    {
        var detector = new DoubleTapDetector();
        detector.HandleDown(0, isRecording: false);
        detector.HandleDown(0.3, isRecording: false);
        Assert.Equal(DoubleTapDetector.Action.Ignored, detector.HandleDown(0.4, isRecording: true));
    }

    [Fact]
    public void NachDerSperrfristStopptDerTipp()
    {
        var detector = new DoubleTapDetector();
        detector.HandleDown(0, isRecording: false);
        detector.HandleDown(0.3, isRecording: false);
        Assert.Equal(DoubleTapDetector.Action.Stop, detector.HandleDown(0.7, isRecording: true));
    }

    [Fact]
    public void ResetVergisstDenOffenenTipp()
    {
        var detector = new DoubleTapDetector();
        detector.HandleDown(0, isRecording: false);
        detector.Reset();
        Assert.Equal(DoubleTapDetector.Action.Armed, detector.HandleDown(0.2, isRecording: false));
    }
}

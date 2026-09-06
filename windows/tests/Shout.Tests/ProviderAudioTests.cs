using Shout.Core;
using Xunit;

namespace Shout.Tests;

/// <summary>WAV-Kopf, Fensterung und die Modell-Vorauswahl fürs Audio.</summary>
public class ProviderAudioTests
{
    // MARK: WAV

    [Fact]
    public void KopfHatDieVereinbartenWerte()
    {
        var wav = WavEncoder.Data(new[] { 0f, 1f, -1f, 2f });

        Assert.Equal(WavEncoder.HeaderBytes + 8, wav.Length);
        Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(wav, 0, 4));
        Assert.Equal("WAVE", System.Text.Encoding.ASCII.GetString(wav, 8, 4));
        Assert.Equal("fmt ", System.Text.Encoding.ASCII.GetString(wav, 12, 4));
        Assert.Equal("data", System.Text.Encoding.ASCII.GetString(wav, 36, 4));

        Assert.Equal(36u + 8, BitConverter.ToUInt32(wav, 4));
        Assert.Equal(16u, BitConverter.ToUInt32(wav, 16));       // Länge des fmt-Blocks
        Assert.Equal(1, BitConverter.ToUInt16(wav, 20));         // PCM
        Assert.Equal(1, BitConverter.ToUInt16(wav, 22));         // Mono
        Assert.Equal(16_000u, BitConverter.ToUInt32(wav, 24));
        Assert.Equal(32_000u, BitConverter.ToUInt32(wav, 28));   // 16 kHz · Mono · 2 Byte
        Assert.Equal(2, BitConverter.ToUInt16(wav, 32));         // Bytes je Rahmen
        Assert.Equal(16, BitConverter.ToUInt16(wav, 34));
        Assert.Equal(8u, BitConverter.ToUInt32(wav, 40));
    }

    /// <summary>Übersteuertes Diktat: begrenzen, nicht überlaufen lassen.</summary>
    [Fact]
    public void SamplesWerdenBegrenzt()
    {
        var wav = WavEncoder.Data(new[] { 0f, 1f, -1f, 2f, -7f });

        Assert.Equal(0, BitConverter.ToInt16(wav, 44));
        Assert.Equal(32_767, BitConverter.ToInt16(wav, 46));
        Assert.Equal(-32_767, BitConverter.ToInt16(wav, 48));
        Assert.Equal(32_767, BitConverter.ToInt16(wav, 50));
        Assert.Equal(-32_767, BitConverter.ToInt16(wav, 52));
    }

    /// <summary>Die 25-MB-Grenze der Endpunkte sind rund 13 Minuten.</summary>
    [Fact]
    public void GrenzeEntsprichtDreizehnMinuten()
    {
        var sekunden = WavEncoder.SecondsFitting(25 * 1024 * 1024);
        Assert.InRange(sekunden, 780, 840);
        Assert.Equal(0, WavEncoder.SecondsFitting(10));
    }

    // MARK: Fensterung

    private static float[] Ton(int laenge, float pegel = 0.5f)
    {
        var samples = new float[laenge];
        for (var i = 0; i < laenge; i++) samples[i] = i % 2 == 0 ? pegel : -pegel;
        return samples;
    }

    [Fact]
    public void KurzesAudioBleibtEinFenster()
    {
        var fenster = AudioWindows.Split(Ton(8_000), 16_000, maxSeconds: 1);
        var einziges = Assert.Single(fenster);
        Assert.Equal(0, einziges.Start);
        Assert.Equal(8_000, einziges.Length);
        Assert.Equal(0, einziges.OffsetSeconds);
    }

    [Fact]
    public void LeeresAudioErgibtKeinFenster()
    {
        Assert.Empty(AudioWindows.Split(Array.Empty<float>()));
    }

    /// <summary>Ohne Überlappung heißt: lückenlos aneinander, nichts doppelt.</summary>
    [Fact]
    public void LangesAudioWirdLueckenlosGeteilt()
    {
        var samples = Ton(56_000);   // 3,5 s bei 16 kHz
        var fenster = AudioWindows.Split(samples, 16_000, maxSeconds: 1, searchSeconds: 0.5);

        Assert.True(fenster.Count > 1);
        Assert.Equal(0, fenster[0].Start);
        Assert.Equal(samples.Length, fenster[^1].End);

        for (var i = 0; i < fenster.Count; i++)
        {
            Assert.True(fenster[i].Length > 0);
            Assert.Equal((double)fenster[i].Start / 16_000, fenster[i].OffsetSeconds, 6);
            if (i > 0) Assert.Equal(fenster[i - 1].End, fenster[i].Start);
            Assert.True(fenster[i].Length <= 16_000);
        }
    }

    /// <summary>Geschnitten wird in der Sprechpause, nicht stur nach der Uhr.</summary>
    [Fact]
    public void SchnittLiegtInDerStille()
    {
        var samples = Ton(40_000);
        for (var i = 12_000; i < 13_000; i++) samples[i] = 0;

        var fenster = AudioWindows.Split(samples, 16_000, maxSeconds: 1, searchSeconds: 0.5);

        Assert.InRange(fenster[0].End, 12_000, 13_000);
    }

    // MARK: Modell-Vorauswahl

    [Fact]
    public void FilterBehaeltNurTranskriptionsModelle()
    {
        var gefiltert = AudioModelFilter.Apply(new[]
            { "gpt-5-mini", "whisper-large-v3", "voxtral-mini-latest", "claude-sonnet-4.5" });

        Assert.Equal(new[] { "whisper-large-v3", "voxtral-mini-latest" }, gefiltert);
    }

    /// <summary>Bleibt nichts übrig, hat der Filter die Namensgebung nur nicht erkannt —
    /// eine ungefilterte Liste ist besser als eine leere.</summary>
    [Fact]
    public void OhneTrefferWirdNichtGefiltert()
    {
        var alle = new[] { "modell-a", "modell-b" };
        Assert.Equal(alle, AudioModelFilter.Apply(alle));
        Assert.Empty(AudioModelFilter.Apply(Array.Empty<string>()));
    }
}

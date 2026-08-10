using NAudio.Wave;

namespace Shout.Core;

/// <summary>Ein Block dekodierter Samples mit seiner Startzeit in der Datei.</summary>
public readonly record struct MediaBlock(float[] Samples, double StartTime);

public sealed class MediaDecoderException : Exception
{
    public MediaDecoderException(string message) : base(message) { }
}

/// <summary>
/// Liest eine Audio- oder Videodatei als Folge von 16-kHz-Mono-Blöcken
/// (Mac: MediaDecoder.swift).
///
/// <para><see cref="MediaFoundationReader"/> statt <c>AudioFileReader</c>: Die
/// Media Foundation dekodiert nicht nur MP3/M4A/WAV, sondern zieht auch die
/// Tonspur aus MP4 und MOV. Dadurch braucht die Windows-Fassung kein FFmpeg —
/// NAudio ist ohnehin schon für die Mikrofonaufnahme da.</para>
///
/// <para>Blockweise statt „ganze Datei in den Speicher": Eine Stunde Audio wären
/// als float-Array rund 230 MB. Blockweise bleibt es bei rund 8 MB, und der
/// Fortschritt lässt sich ehrlich melden.</para>
/// </summary>
public sealed class MediaDecoder : IDisposable
{
    public const int SampleRate = 16_000;

    private readonly int blockSamples;
    private readonly int searchSamples;
    private MediaFoundationReader? reader;
    private ISampleProvider? samples;

    /// <summary>Noch nicht ausgegebene Samples (Rest des letzten Blocks + neu gelesene).</summary>
    private readonly List<float> pending = new();
    /// <summary>Bereits ausgegebene Samples — daraus entsteht die nächste Startzeit.</summary>
    private long emitted;
    private bool finished;

    public MediaDecoder(double blockSeconds = 120, double searchSeconds = 30)
    {
        blockSamples = (int)(blockSeconds * SampleRate);
        searchSamples = (int)(searchSeconds * SampleRate);
    }

    /// <summary>Öffnet die Datei und liefert ihre Dauer in Sekunden.</summary>
    public double Open(string path)
    {
        try
        {
            reader = new MediaFoundationReader(path);
        }
        catch (Exception ex)
        {
            throw new MediaDecoderException(ex.Message);
        }

        if (reader.WaveFormat.Channels == 0)
            throw new MediaDecoderException(Loc.T("Diese Datei enthält keine Tonspur."));

        // Auf 16 kHz Mono bringen: erst zu Mono mischen, dann neu abtasten.
        // Die Reihenfolge spart dem Resampler die Hälfte der Arbeit.
        ISampleProvider provider = reader.ToSampleProvider();
        if (provider.WaveFormat.Channels > 1)
            provider = new NAudio.Wave.SampleProviders.StereoToMonoSampleProvider(provider);
        if (provider.WaveFormat.SampleRate != SampleRate)
            provider = new NAudio.Wave.SampleProviders.WdlResamplingSampleProvider(provider, SampleRate);

        samples = provider;
        return reader.TotalTime.TotalSeconds;
    }

    /// <summary>Nächster Block — <c>null</c>, wenn die Datei zu Ende ist.</summary>
    public MediaBlock? Next()
    {
        if (samples == null || finished) return null;

        var buffer = new float[16_000];
        while (pending.Count < blockSamples)
        {
            var read = samples.Read(buffer, 0, buffer.Length);
            if (read <= 0) break;
            pending.AddRange(buffer.AsSpan(0, read).ToArray());
        }

        if (pending.Count == 0)
        {
            finished = true;
            return null;
        }

        var cut = pending.Count >= blockSamples
            ? CutIndex(pending, blockSamples, searchSamples, SampleRate / 2)
            : pending.Count;

        var block = new MediaBlock(pending.GetRange(0, cut).ToArray(), (double)emitted / SampleRate);
        emitted += cut;
        pending.RemoveRange(0, cut);
        return block;
    }

    /// <summary>
    /// Schnittstelle für einen vollen Block: die Mitte des leisesten Fensters im
    /// hinteren Bereich. So fällt die Blockgrenze auf eine Sprechpause statt mitten
    /// in ein Wort.
    /// </summary>
    public static int CutIndex(IReadOnlyList<float> samples, int blockSamples,
                               int searchSamples, int windowSamples)
    {
        if (samples.Count < blockSamples || windowSamples <= 1) return samples.Count;
        var searchStart = Math.Max(0, blockSamples - searchSamples);
        if (searchStart + windowSamples > blockSamples) return blockSamples;

        var bestIndex = -1;
        var bestRms = float.MaxValue;
        var step = Math.Max(1, windowSamples / 2);   // 50 % Überlappung
        for (var i = searchStart; i + windowSamples <= blockSamples; i += step)
        {
            float sum = 0;
            for (var j = i; j < i + windowSamples; j++) sum += samples[j] * samples[j];
            var rms = MathF.Sqrt(sum / windowSamples);
            if (rms >= bestRms) continue;
            bestRms = rms;
            bestIndex = i;
        }
        return bestIndex < 0 ? blockSamples : Math.Min(blockSamples, bestIndex + windowSamples / 2);
    }

    public void Dispose()
    {
        reader?.Dispose();
        reader = null;
        samples = null;
        pending.Clear();
    }
}

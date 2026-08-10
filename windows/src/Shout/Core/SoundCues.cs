using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Shout.Core;

/// <summary>
/// Die Klang-Signale der App (Mac: SoundCues.swift). Statt der Windows-Systemtöne
/// dieselben Dateien wie am Mac, damit die App überall gleich klingt.
///
/// <para>Die Dateien sind unterschiedlich laut ausgesteuert — gemessen lagen Start
/// und Stopp bei −1 dBFS Spitze, der Fehlerton rund 10 dB darunter. Deshalb wird
/// beim Laden gemessen und angeglichen, statt feste Faktoren je Datei zu pflegen:
/// So bleibt die Lautstärke stimmig, wenn die Klänge ausgetauscht werden.</para>
/// </summary>
public sealed class SoundCues : IDisposable
{
    public enum Cue { Start, Done, Error }

    /// <summary>Zielwert der wahrgenommenen Lautstärke (RMS der lautesten 300 ms),
    /// linear. 0,05 entspricht etwa −26 dBFS: deutlich hörbar, aber nichts, was
    /// einen bei Kopfhörern zusammenzucken lässt.</summary>
    private const float TargetLoudness = 0.05f;
    /// <summary>Obergrenze für den Spitzenwert (≈ −12 dBFS).</summary>
    private const float MaxPeak = 0.25f;

    /// <summary>Format der Wiedergabe. Wird aus der ersten geladenen Datei
    /// übernommen, statt fest auf 44,1 kHz zu stehen: Die Klänge liegen in 48 kHz
    /// vor, und sie vorab umzurechnen klingt hörbar schlechter (krummes Verhältnis).
    /// Die Umrechnung auf die Hardware-Rate macht die Audio-Ausgabe von Windows.</summary>
    private WaveFormat? format;

    private readonly Dictionary<Cue, float[]> samples = new();
    private WaveOutEvent? output;
    private BufferedWaveProvider? buffer;
    private readonly object gate = new();

    public SoundCues()
    {
        Load(Cue.Start, "Rec_start.mp3");
        // „Fertig eingefügt" nutzt den Stopp-Klang: Es ist die eigentlich nützliche
        // Rückmeldung („du kannst weiterarbeiten").
        Load(Cue.Done, "Rec_stop.mp3");
        Load(Cue.Error, "Error_sound.mp3");
    }

    public void Play(Cue cue)
    {
        if (!Settings.Shared.SoundCuesEnabled) return;
        if (format == null) return;
        if (!samples.TryGetValue(cue, out var data) || data.Length == 0) return;

        try
        {
            lock (gate)
            {
                if (output == null)
                {
                    buffer = new BufferedWaveProvider(format!)
                    {
                        BufferDuration = TimeSpan.FromSeconds(5),
                        DiscardOnBufferOverflow = true,
                    };
                    output = new WaveOutEvent();
                    output.Init(buffer);
                }
                // Laufenden Klang abschneiden: Zwei Signale übereinander klingen nach
                // Fehler, auch wenn keiner vorliegt.
                buffer!.ClearBuffer();
                var bytes = new byte[data.Length * sizeof(float)];
                Buffer.BlockCopy(data, 0, bytes, 0, bytes.Length);
                buffer.AddSamples(bytes, 0, bytes.Length);
                if (output!.PlaybackState != PlaybackState.Playing) output.Play();
            }
        }
        catch (Exception ex)
        {
            // Kein Audio-Gerät, belegte Ausgabe … — ein fehlender Ton darf das Diktat
            // nicht stören.
            System.Diagnostics.Debug.WriteLine($"SoundCues: {ex.Message}");
        }
    }

    // MARK: - Laden

    private void Load(Cue cue, string resourceName)
    {
        try
        {
            using var stream = typeof(SoundCues).Assembly
                .GetManifestResourceStream(resourceName);
            if (stream == null) return;

            using var reader = new Mp3FileReader(stream);
            ISampleProvider provider = reader.ToSampleProvider();

            // Format der ERSTEN Datei gilt für alle: Nur wer davon abweicht, wird
            // umgerechnet — und das ist der Ausnahmefall, nicht die Regel.
            format ??= WaveFormat.CreateIeeeFloatWaveFormat(
                provider.WaveFormat.SampleRate, Math.Max(1, provider.WaveFormat.Channels));

            if (provider.WaveFormat.Channels == 1 && format.Channels == 2)
                provider = new MonoToStereoSampleProvider(provider);
            if (provider.WaveFormat.SampleRate != format.SampleRate)
                provider = new WdlResamplingSampleProvider(provider, format.SampleRate);

            var all = new List<float>();
            var chunk = new float[8_192];
            int read;
            while ((read = provider.Read(chunk, 0, chunk.Length)) > 0)
                all.AddRange(chunk.Take(read));

            var data = all.ToArray();
            Normalize(data);
            samples[cue] = data;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SoundCues: {resourceName} nicht ladbar — {ex.Message}");
        }
    }

    /// <summary>
    /// Hebt oder senkt den Klang auf die Ziel-Lautstärke.
    ///
    /// <para>Gemessen wird die lauteste 300-Millisekunden-Strecke, nicht der
    /// Gesamt-RMS: Über die Gesamtlänge zu mitteln würde einen langen Klang mit viel
    /// Stille künstlich hochziehen — genau der Fall des 1,8 Sekunden langen
    /// Fehlertons.</para>
    /// </summary>
    private void Normalize(float[] data)
    {
        if (data.Length == 0 || format == null) return;
        var channels = format.Channels;
        var frames = data.Length / channels;
        if (frames == 0) return;

        var mono = new float[frames];
        var peak = 0f;
        for (var i = 0; i < frames; i++)
        {
            var sum = 0f;
            for (var c = 0; c < channels; c++) sum += data[i * channels + c];
            var value = sum / channels;
            mono[i] = value;
            peak = Math.Max(peak, Math.Abs(value));
        }
        if (peak <= 0) return;

        var window = Math.Min(frames, (int)(format.SampleRate * 0.3));
        var energy = 0f;
        for (var i = 0; i < window; i++) energy += mono[i] * mono[i];
        var best = energy;
        for (var i = window; i < frames; i++)
        {
            energy += mono[i] * mono[i] - mono[i - window] * mono[i - window];
            best = Math.Max(best, energy);
        }
        var loudness = MathF.Sqrt(best / window);
        if (loudness <= 0) return;

        var gain = Math.Min(TargetLoudness / loudness, MaxPeak / peak);
        if (Math.Abs(gain - 1f) < 0.001f) return;
        for (var i = 0; i < data.Length; i++) data[i] *= gain;
    }

    public void Dispose()
    {
        lock (gate)
        {
            output?.Dispose();
            output = null;
            buffer = null;
        }
    }
}

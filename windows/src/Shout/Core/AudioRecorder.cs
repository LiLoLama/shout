using NAudio.Wave;

namespace Shout.Core;

/// <summary>
/// Nimmt Mikrofon-Audio auf und liefert es als 16-kHz-Mono-Float-Array — genau
/// das Format, das Whisper erwartet. Port der Mac-Logik: adaptiver VAD
/// (Rausch-Boden als Minimum-Tracker), Auto-Stopp nach Stille, Stille-Trimmen.
///
/// WaveInEvent mit 16 kHz/16 bit/mono — der Windows-Wave-Mapper resampled
/// transparent von der Hardware-Rate. Der DataAvailable-Callback läuft auf
/// einem Audio-Thread, daher ist der Sample-Puffer per Lock geschützt.
/// </summary>
public sealed class AudioRecorder : IDisposable
{
    private WaveInEvent? waveIn;

    private readonly object gate = new();
    private readonly List<float> samples = new();
    /// <summary>Zählt jede Aufnahme hoch; verspätete Callbacks einer alten
    /// Aufnahme tragen eine ältere Generation und werden ignoriert.</summary>
    private int generation;

    private const int SampleRate = 16_000;

    // MARK: Auto-Stopp (Stille-Erkennung)

    public bool AutoStopEnabled { get; set; }
    public double SilenceSeconds { get; set; } = 1.5;
    /// <summary>Wird einmal gefeuert, wenn nach erkannter Sprache lang genug Stille war.</summary>
    public event Action? OnSilence;
    /// <summary>Laufender Eingangspegel 0…1 (für die Aufnahme-Anzeige).</summary>
    public event Action<float>? OnLevel;

    // Adaptiver VAD — Parameter identisch zum Mac.
    private float noiseFloor = 0.01f;
    private const float SpeechFactor = 3.5f;     // wie weit über dem Rauschen = Sprache
    private const float AbsoluteFloor = 0.010f;  // unter diesem RMS ist es immer „still"

    private bool heardSpeech;
    private double silenceAccumulated;
    private bool silenceFired;

    public void Start()
    {
        int gen;
        lock (gate)
        {
            samples.Clear();
            generation++;
            gen = generation;
            heardSpeech = false;
            silenceAccumulated = 0;
            silenceFired = false;
            noiseFloor = 0.01f;   // Rausch-Boden je Aufnahme neu einpendeln lassen
        }

        waveIn?.Dispose();
        waveIn = new WaveInEvent
        {
            WaveFormat = new WaveFormat(SampleRate, 16, 1),
            BufferMilliseconds = 100,
        };
        waveIn.DataAvailable += (_, e) => Append(e, gen);
        waveIn.StartRecording();
    }

    /// <summary>Beendet die Aufnahme und gibt die gesammelten Samples zurück
    /// (führende/abschließende Stille bereits weggetrimmt).</summary>
    public float[] Stop()
    {
        // Den letzten in-flight Puffer (~100 ms) noch ankommen lassen, damit das
        // Ende des letzten Wortes nicht abgeschnitten wird.
        Thread.Sleep(90);
        waveIn?.StopRecording();
        waveIn?.Dispose();
        waveIn = null;

        float[] result;
        lock (gate)
        {
            result = samples.ToArray();
            samples.Clear();
        }
        return TrimSilence(result);
    }

    public void Dispose()
    {
        waveIn?.Dispose();
        waveIn = null;
    }

    // MARK: Intern

    private void Append(WaveInEventArgs e, int gen)
    {
        // 16-bit-PCM → Float −1…1.
        var count = e.BytesRecorded / 2;
        if (count == 0) return;
        var chunk = new float[count];
        for (var i = 0; i < count; i++)
            chunk[i] = BitConverter.ToInt16(e.Buffer, i * 2) / 32768f;

        lock (gate)
        {
            if (gen != generation) return;   // Callback einer alten Aufnahme
            samples.AddRange(chunk);
        }

        Analyze(chunk, gen);
    }

    /// <summary>Berechnet einmal den RMS-Pegel und nutzt ihn für Live-Pegel +
    /// Stille-Erkennung — VAD-Logik identisch zum Mac.</summary>
    private void Analyze(float[] chunk, int gen)
    {
        float sumSquares = 0;
        foreach (var s in chunk) sumSquares += s * s;
        var rms = MathF.Sqrt(sumSquares / chunk.Length);

        // Live-Pegel 0…1: sqrt-Kurve für kräftigeren Ausschlag, mit kleinem Rauschabzug.
        var level = Math.Min(1f, Math.Max(0f, MathF.Sqrt(rms) - 0.04f) * 5.5f);
        OnLevel?.Invoke(level);

        var duration = (double)chunk.Length / SampleRate;
        var fireSilence = false;

        lock (gate)
        {
            if (gen != generation) return;
            // Rausch-Boden als Minimum-Tracker: folgt leisen Fenstern schnell nach
            // unten, „vergisst" nach oben nur sehr langsam, hart gedeckelt. Er darf
            // NICHT aus Sprach-Chunks lernen — sonst klettert er bei Dauersprechen
            // über den Sprechpegel und Sprache gilt als „Stille".
            if (rms < noiseFloor)
                noiseFloor = noiseFloor * 0.5f + rms * 0.5f;
            else
                noiseFloor = Math.Min(noiseFloor * 1.002f, 0.015f);

            var threshold = Math.Max(AbsoluteFloor, noiseFloor * SpeechFactor);
            if (AutoStopEnabled && !silenceFired)
            {
                if (rms > threshold)
                {
                    heardSpeech = true;
                    silenceAccumulated = 0;
                }
                else if (heardSpeech)
                {
                    silenceAccumulated += duration;
                    if (silenceAccumulated >= SilenceSeconds)
                    {
                        silenceFired = true;
                        fireSilence = true;
                    }
                }
            }
        }

        if (fireSilence) OnSilence?.Invoke();
    }

    /// <summary>
    /// Schneidet führende/abschließende Stille weg, bevor die Samples an Whisper
    /// gehen (weniger Halluzinationen, geringere Latenz). Schwelle RELATIV zum
    /// lautesten Fenster, eng gedeckelt — Parameter identisch zum Mac.
    /// </summary>
    private static float[] TrimSilence(float[] input)
    {
        if (input.Length <= 3_200) return input;   // < 0,2 s: unverändert lassen
        const int window = 480;                     // 30 ms bei 16 kHz

        var windowRms = new List<float>(input.Length / window + 1);
        for (var i = 0; i < input.Length; i += window)
        {
            var end = Math.Min(i + window, input.Length);
            float sum = 0;
            for (var j = i; j < end; j++) sum += input[j] * input[j];
            windowRms.Add(MathF.Sqrt(sum / (end - i)));
        }

        var peak = windowRms.Count > 0 ? windowRms.Max() : 0;
        if (peak < 0.008f) return Array.Empty<float>();   // nie substanzielle Energie → still

        // 10 % des Peaks, geklemmt auf [0.004, 0.012] — leise Sprecher bleiben
        // drin, echtes Grundrauschen bleibt draußen.
        var threshold = Math.Min(Math.Max(0.004f, peak * 0.10f), 0.012f);

        int firstSpeech = -1, lastSpeech = -1;
        for (var w = 0; w < windowRms.Count; w++)
        {
            if (windowRms[w] <= threshold) continue;
            if (firstSpeech < 0) firstSpeech = w * window;
            lastSpeech = Math.Min(w * window + window, input.Length);
        }

        if (firstSpeech < 0) return Array.Empty<float>();
        const int pad = 4_800;                      // 300 ms Sicherheitsrand
        var start = Math.Max(0, firstSpeech - pad);
        var stop = Math.Min(input.Length, lastSpeech + pad);
        return input[start..stop];
    }
}

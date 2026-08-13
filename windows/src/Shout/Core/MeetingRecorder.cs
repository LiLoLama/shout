using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Shout.Core;

/// <summary>Woher der Ton kommt (Mac: MeetingSource in MeetingRecorder.swift).</summary>
public enum MeetingSource { Microphone, SystemAudio, Both }

/// <summary>
/// Nimmt eine Besprechung auf und schreibt sie **direkt in eine Datei**
/// (Mac: MeetingRecorder.swift).
///
/// <para>Bewusst getrennt vom Diktat-Recorder: Der sammelt im Arbeitsspeicher und
/// stoppt bei einer Sprechpause von selbst — beides ist hier falsch.</para>
///
/// <para>Geschrieben wird WAV in 16 kHz Mono, also rund 115 MB pro Stunde. Am Mac
/// ist es AAC mit 8 MB; ein Encoder unter Windows würde MediaFoundation brauchen,
/// das den ganzen Strom am Stück verlangt und für eine laufende Aufnahme nicht
/// taugt. Platte ist billiger als eine abgebrochene Stunde.</para>
///
/// <para>Der Systemton kommt über <see cref="WasapiLoopbackCapture"/> — das ist der
/// Ton, den andere Programme ausgeben (Zoom, Teams, Meet). Anders als am Mac
/// braucht das keine gesonderte Berechtigung.</para>
/// </summary>
public sealed class MeetingRecorder : IDisposable
{
    private const int Rate = 16_000;

    private WasapiCapture? microphone;
    private WasapiLoopbackCapture? system;
    private WaveFileWriter? writer;
    private readonly object gate = new();

    /// <summary>Ein Puffer je Quelle. Bei „beides" laufen zwei Geräte mit eigenen
    /// Uhren; gemischt wird, was gleichzeitig vorliegt.</summary>
    private BufferedWaveProvider? microphoneBuffer;
    private BufferedWaveProvider? systemBuffer;
    private ISampleProvider? mix;
    private System.Threading.Timer? pump;

    private long framesWritten;
    private bool paused;
    private bool sawSignal;

    public bool IsRecording { get; private set; }
    public bool IsPaused { get; private set; }
    /// <summary>Aufgenommene Zeit, aus den geschriebenen Frames gerechnet und nicht
    /// aus der Uhr — so zählt eine Pause exakt nicht mit.</summary>
    public double Duration => framesWritten / (double)Rate;
    public float Level { get; private set; }
    /// <summary>Läuft die Aufnahme, ohne dass je ein Ton ankam? Dann stimmt etwas
    /// mit der Quelle nicht — ohne diesen Hinweis stünde man nach einer Stunde vor
    /// einer stummen Datei.</summary>
    public bool NoSignal { get; private set; }

    public string? Path { get; private set; }

    public event Action? Changed;

    // MARK: - Ablage

    /// <summary>Ordner für Mitschnitte. Sie bleiben liegen, auch nach der
    /// Verarbeitung: Eine Stunde Meeting kann man nicht neu aufnehmen.</summary>
    public static string RecordingsDirectory()
    {
        var dir = RecordingsPath;
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static string RecordingsPath =>
        System.IO.Path.Combine(StoreIO.DataDirectory, "Recordings");

    public static IReadOnlyList<string> ExistingRecordings()
    {
        if (!Directory.Exists(RecordingsPath)) return Array.Empty<string>();
        return Directory.GetFiles(RecordingsPath, "*.wav")
            .OrderByDescending(File.GetLastWriteTimeUtc).ToList();
    }

    /// <summary>Stammt die Datei aus unserem Mitschnitt-Ordner? Nur solche darf die
    /// App von sich aus löschen oder umbenennen.</summary>
    public static bool IsOwnRecording(string path)
    {
        try
        {
            var dir = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(path));
            return string.Equals(dir, System.IO.Path.GetFullPath(RecordingsPath),
                                 StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    /// <summary>„Meeting 2026-08-12 09-15.wav" — ohne Zeichen, die Pfade stören.</summary>
    public static string FileName(DateTime when) =>
        $"Meeting {when:yyyy-MM-dd HH-mm}.wav";

    /// <summary>Macht aus einer Eingabe einen brauchbaren Dateinamen.</summary>
    public static string? SafeName(string raw)
    {
        var name = raw.Trim();
        foreach (var c in System.IO.Path.GetInvalidFileNameChars())
            name = name.Replace(c, '-');
        name = name.TrimStart('.');
        if (name.Length > 80) name = name[..80];
        name = name.Trim();
        return name.Length == 0 ? null : name;
    }

    /// <summary>Freier Platz: „Kickoff", sonst „Kickoff 2", „Kickoff 3" …</summary>
    public static string FreeTarget(string directory, string name, string extension)
    {
        var target = System.IO.Path.Combine(directory, name + extension);
        var suffix = 2;
        while (File.Exists(target))
            target = System.IO.Path.Combine(directory, $"{name} {suffix++}{extension}");
        return target;
    }

    /// <summary>Benennt einen Mitschnitt um und nimmt das Transkript daneben mit.
    /// Gibt die neue Adresse zurück — oder die alte, wenn nichts zu tun war.</summary>
    public static string Rename(string path, string raw)
    {
        var name = SafeName(raw);
        if (!IsOwnRecording(path) || name == null) return path;
        var directory = System.IO.Path.GetDirectoryName(path)!;
        var extension = System.IO.Path.GetExtension(path);
        // Unveränderter Name ZUERST — sonst schöbe die Suche nach einem freien
        // Platz an der Datei selbst vorbei und machte „Kickoff 2" daraus.
        if (string.Equals(System.IO.Path.Combine(directory, name + extension), path,
                          StringComparison.OrdinalIgnoreCase)) return path;

        var target = FreeTarget(directory, name, extension);
        try { File.Move(path, target); }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Mitschnitt nicht umbenannt: {ex.Message}");
            return path;
        }
        // Anders als am iPhone gibt es hier keine Transkript-Ablage neben der
        // Datei — Ergebnisse leben unter Windows wie am Mac nur zur Laufzeit.
        return target;
    }

    // MARK: - Steuerung

    public string Start(MeetingSource source)
    {
        if (IsRecording) throw new InvalidOperationException(Loc.T("Es läuft bereits eine Aufnahme."));

        var target = System.IO.Path.Combine(RecordingsDirectory(), FileName(DateTime.Now));
        var format = new WaveFormat(Rate, 16, 1);
        writer = new WaveFileWriter(target, format);
        Path = target;
        framesWritten = 0;
        paused = false;
        sawSignal = false;
        NoSignal = false;
        Level = 0;

        try
        {
            var providers = new List<ISampleProvider>();
            if (source is MeetingSource.Microphone or MeetingSource.Both)
                providers.Add(StartMicrophone());
            if (source is MeetingSource.SystemAudio or MeetingSource.Both)
                providers.Add(StartSystem());

            mix = providers.Count == 1
                ? providers[0]
                // Bei zwei Quellen halbieren, damit die Summe nicht übersteuert.
                : new MixingSampleProvider(providers) { ReadFully = true }
                    .ToSampleProvider2(0.5f);

            // Die beiden Geräte laufen auf eigenen Uhren; ein Zeitgeber holt ab,
            // was vorliegt. Läuft ein Puffer voll (Drift), wird vorne verworfen —
            // lieber ein Aussetzer als wachsende Verzögerung über eine Stunde.
            pump = new System.Threading.Timer(_ => Pump(), null, 100, 100);
        }
        catch
        {
            // Angefangene Datei nicht liegen lassen, sonst taucht ein leerer
            // Mitschnitt in der Liste auf.
            Teardown();
            writer?.Dispose();
            writer = null;
            try { File.Delete(target); } catch { }
            Path = null;
            throw;
        }

        IsRecording = true;
        IsPaused = false;
        Changed?.Invoke();
        return target;
    }

    private ISampleProvider StartMicrophone()
    {
        microphone = new WasapiCapture();
        microphoneBuffer = MakeBuffer(microphone.WaveFormat);
        microphone.DataAvailable += (_, e) => microphoneBuffer?.AddSamples(e.Buffer, 0, e.BytesRecorded);
        microphone.StartRecording();
        return Resampled(microphoneBuffer, microphone.WaveFormat);
    }

    private ISampleProvider StartSystem()
    {
        system = new WasapiLoopbackCapture();
        systemBuffer = MakeBuffer(system.WaveFormat);
        system.DataAvailable += (_, e) => systemBuffer?.AddSamples(e.Buffer, 0, e.BytesRecorded);
        system.StartRecording();
        return Resampled(systemBuffer, system.WaveFormat);
    }

    private static BufferedWaveProvider MakeBuffer(WaveFormat format) => new(format)
    {
        // Fünf Sekunden Vorrat: genug gegen Ruckler, wenig genug, dass ein
        // driftendes Gerät die Aufnahme nicht immer weiter hinterherhinken lässt.
        BufferDuration = TimeSpan.FromSeconds(5),
        DiscardOnBufferOverflow = true,
        ReadFully = true,
    };

    private static ISampleProvider Resampled(BufferedWaveProvider buffer, WaveFormat format)
    {
        ISampleProvider provider = buffer.ToSampleProvider();
        if (format.Channels > 1) provider = new StereoToMonoSampleProvider(provider);
        if (format.SampleRate != Rate) provider = new WdlResamplingSampleProvider(provider, Rate);
        return provider;
    }

    /// <summary>Holt ab, was vorliegt, und schreibt es. Läuft auf dem Zeitgeber,
    /// nicht auf dem Audio-Thread — die Datei-Ausgabe gehört dort nicht hin.</summary>
    private void Pump()
    {
        lock (gate)
        {
            if (!IsRecording || mix == null || writer == null) return;

            var wanted = Rate / 10;   // 100 ms
            var samples = new float[wanted];
            var read = mix.Read(samples, 0, wanted);
            if (read <= 0) return;

            float peak = 0;
            for (var i = 0; i < read; i++) peak = Math.Max(peak, Math.Abs(samples[i]));
            Level = paused ? 0 : Math.Min(1f, peak * 2.2f);
            if (peak > 0.0001f) { sawSignal = true; NoSignal = false; }
            else if (!sawSignal && Duration > 6) NoSignal = true;

            if (paused) { Changed?.Invoke(); return; }

            var bytes = new byte[read * 2];
            for (var i = 0; i < read; i++)
            {
                var value = (short)(Math.Clamp(samples[i], -1f, 1f) * short.MaxValue);
                bytes[i * 2] = (byte)(value & 0xFF);
                bytes[i * 2 + 1] = (byte)((value >> 8) & 0xFF);
            }
            writer.Write(bytes, 0, bytes.Length);
            framesWritten += read;
            Changed?.Invoke();
        }
    }

    public void Pause()
    {
        if (!IsRecording || IsPaused) return;
        paused = true;
        IsPaused = true;
        Changed?.Invoke();
    }

    public void Resume()
    {
        if (!IsRecording || !IsPaused) return;
        paused = false;
        IsPaused = false;
        Changed?.Invoke();
    }

    /// <summary>Beendet die Aufnahme und gibt die fertige Datei zurück.</summary>
    public string? Stop()
    {
        if (!IsRecording) return null;
        Teardown();
        lock (gate)
        {
            writer?.Dispose();
            writer = null;
        }
        var finished = Path;
        Path = null;
        Changed?.Invoke();
        return finished;
    }

    /// <summary>Bricht ab und löscht die angefangene Datei.</summary>
    public void Cancel()
    {
        var started = Stop();
        if (started != null) { try { File.Delete(started); } catch { } }
    }

    private void Teardown()
    {
        pump?.Dispose();
        pump = null;
        microphone?.StopRecording();
        microphone?.Dispose();
        microphone = null;
        system?.StopRecording();
        system?.Dispose();
        system = null;
        microphoneBuffer = null;
        systemBuffer = null;
        mix = null;
        IsRecording = false;
        IsPaused = false;
        paused = false;
        Level = 0;
        NoSignal = false;
    }

    public void Dispose()
    {
        Teardown();
        writer?.Dispose();
        writer = null;
    }
}

internal static class SampleProviderExtensions
{
    /// <summary>Multipliziert die Lautstärke — NAudios VolumeSampleProvider in
    /// einer Zeile, damit die Mischung zweier Quellen nicht übersteuert.</summary>
    public static ISampleProvider ToSampleProvider2(this ISampleProvider source, float volume)
        => new VolumeSampleProvider(source) { Volume = volume };
}

using System.Text.Json;

namespace Shout.Core;

/// <summary>Das gesicherte Ergebnis eines Mitschnitts (Mac/iOS: StoredTranscript).</summary>
public sealed class StoredTranscript
{
    public string RawText { get; set; } = "";
    public string MinutesText { get; set; } = "";
    /// <summary>Die Segmente kommen mit, obwohl die Liste sie nicht anzeigt: Sie sind
    /// die Grundlage für Untertitel, und sie später aus dem fertigen Text
    /// zurückzurechnen wäre unmöglich.</summary>
    public List<TranscriptSegment> Segments { get; set; } = new();
    public double Duration { get; set; }
}

/// <summary>
/// Legt das Transkript <b>neben die Audiodatei</b> — „Meeting 2026-08-12 09-15.wav"
/// bekommt „Meeting 2026-08-12 09-15.json" (Port von TranscriptStore.swift).
///
/// <para>Ohne das war eine Stunde Mitschnitt nach dem Neustart der App zwar noch da,
/// ihr Transkript aber nicht: Der Auftrag kam als „noch nicht verarbeitet" zurück und
/// musste komplett neu gerechnet werden.</para>
///
/// <para>Kein zentraler Index: Der müsste gepflegt werden und kann von der Wirklichkeit
/// abweichen. So gehört das Ergebnis zur Aufnahme wie ihr Dateiname — wer die Aufnahme
/// entfernt, entfernt beides, und es kann nichts verwaisen.</para>
///
/// <para>Gesichert wird ausschließlich für <b>eigene Mitschnitte</b>. Eingeworfene
/// Dateien liegen beim Nutzer; dort hat die App nichts abzulegen, und auf der Seite
/// „Dateien" steht ausdrücklich, dass nichts automatisch gespeichert wird.</para>
/// </summary>
public static class TranscriptStore
{
    public static string SidecarFor(string audioPath) => Path.ChangeExtension(audioPath, ".json");

    public static void Save(StoredTranscript transcript, string audioPath)
    {
        if (!MeetingRecorder.IsOwnRecording(audioPath)) return;
        try
        {
            var json = JsonSerializer.Serialize(transcript, StoreIO.JsonOptions);
            var target = SidecarFor(audioPath);
            var tmp = target + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, target, overwrite: true);
        }
        catch (Exception ex)
        {
            // Ein verlorenes Transkript ist ärgerlich, aber kein Grund, den fertigen
            // Auftrag scheitern zu lassen — der Text steht ja da.
            StoreIO.Log($"Transkript konnte nicht gesichert werden: {ex.Message}");
        }
    }

    /// <summary>Liest das Transkript neben der Aufnahme. <c>null</c> = keins da oder
    /// beschädigt; der Auftrag steht dann wieder als „noch nicht verarbeitet" da.</summary>
    public static StoredTranscript? Load(string audioPath)
    {
        try
        {
            var path = SidecarFor(audioPath);
            if (!File.Exists(path)) return null;
            var loaded = JsonSerializer.Deserialize<StoredTranscript>(File.ReadAllText(path), StoreIO.JsonOptions);
            if (loaded == null) return null;
            loaded.Segments ??= new List<TranscriptSegment>();
            return loaded;
        }
        catch
        {
            return null;
        }
    }

    public static void Remove(string audioPath)
    {
        try { File.Delete(SidecarFor(audioPath)); } catch { }
    }

    /// <summary>Nimmt das Transkript beim Umbenennen mit.</summary>
    public static void Move(string fromAudio, string toAudio)
    {
        try
        {
            var from = SidecarFor(fromAudio);
            if (File.Exists(from)) File.Move(from, SidecarFor(toAudio), overwrite: true);
        }
        catch (Exception ex)
        {
            StoreIO.Log($"Transkript nicht mitgezogen: {ex.Message}");
        }
    }
}

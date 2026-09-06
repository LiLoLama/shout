using System.Text;

namespace Shout.Core;

/// <summary>
/// Packt Float-Samples als WAV in den Speicher — für den Upload zu einem
/// Transkriptions-Endpunkt.
///
/// <para>WAV und nicht MP3: Die Endpunkte nehmen es alle, es braucht keinen Encoder
/// (und damit keine weitere Abhängigkeit neben NAudio) und die Rechnung ist
/// nachvollziehbar — 16 kHz, Mono, 16 bit sind genau 32.000 Byte je Sekunde. Das ist
/// die Grundlage der Fensterung in <see cref="AudioWindows"/>: Die Größenbeschränkung
/// der Endpunkte (25 MB) entspricht damit rund 13 Minuten.</para>
/// </summary>
public static class WavEncoder
{
    /// <summary>Fester Kopf einer unkomprimierten Mono-WAV-Datei.</summary>
    public const int HeaderBytes = 44;

    public static byte[] Data(float[] samples, int sampleRate = 16_000)
    {
        const int bitsPerSample = 16;
        const int channels = 1;
        const int bytesPerSample = bitsPerSample / 8;
        var dataBytes = samples.Length * bytesPerSample;
        var byteRate = sampleRate * channels * bytesPerSample;

        using var stream = new MemoryStream(HeaderBytes + dataBytes);
        using var writer = new BinaryWriter(stream, Encoding.ASCII);

        writer.Write(Encoding.ASCII.GetBytes("RIFF"));
        writer.Write((uint)(36 + dataBytes));      // Restlänge ab hier
        writer.Write(Encoding.ASCII.GetBytes("WAVE"));
        writer.Write(Encoding.ASCII.GetBytes("fmt "));
        writer.Write(16u);                         // Länge des fmt-Blocks
        writer.Write((ushort)1);                   // PCM, unkomprimiert
        writer.Write((ushort)channels);
        writer.Write((uint)sampleRate);
        writer.Write((uint)byteRate);
        writer.Write((ushort)(channels * bytesPerSample));   // Bytes je Rahmen
        writer.Write((ushort)bitsPerSample);
        writer.Write(Encoding.ASCII.GetBytes("data"));
        writer.Write((uint)dataBytes);

        foreach (var sample in samples)
        {
            // Begrenzen, nicht überlaufen lassen: Ein übersteuertes Diktat würde sonst
            // als Krachen ankommen statt als lautes Sprechen.
            var clamped = Math.Clamp(sample, -1f, 1f);
            writer.Write((short)(clamped * 32_767f));
        }

        writer.Flush();
        return stream.ToArray();
    }

    /// <summary>Wie viele Sekunden Audio in <paramref name="maxBytes"/> passen (Kopf
    /// eingerechnet).</summary>
    public static double SecondsFitting(int maxBytes, int sampleRate = 16_000)
        => Math.Max(0, maxBytes - HeaderBytes) / (double)(sampleRate * 2);
}

using Microsoft.Win32;

namespace Shout.Core;

/// <summary>
/// Prozessor und Arbeitsspeicher für die Modell-Empfehlung — das Windows-Pendant
/// zu `Hardware.chip` der Mac-App.
/// </summary>
public static class Hardware
{
    private static string? cachedChip;

    /// <summary>Prozessor-Bezeichnung (z. B. „AMD Ryzen 7 5800X3D").</summary>
    public static string Chip
    {
        get
        {
            if (cachedChip != null) return cachedChip;
            string? name = null;
            try
            {
                using var key = Registry.LocalMachine.OpenSubKey(
                    @"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
                name = key?.GetValue("ProcessorNameString") as string;
            }
            catch
            {
                // Registry nicht lesbar — dann bleibt es beim Platzhalter unten.
            }
            cachedChip = string.IsNullOrWhiteSpace(name)
                ? $"{Environment.ProcessorCount} CPU-Kerne"
                : name.Trim();
            return cachedChip;
        }
    }

    public static int MemoryGB => ModelCatalog.PhysicalMemoryGB();

    /// <summary>Kerne (logisch) — ergänzt die Zeile unter dem Prozessornamen.</summary>
    public static int Cores => Environment.ProcessorCount;
}

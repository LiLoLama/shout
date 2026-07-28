namespace Shout.Core;

/// <summary>
/// Modell-Katalog für Windows: Whisper-Modelle als ggml (whisper.cpp) und
/// Formatierungs-LLMs als GGUF (llama.cpp), beide direkt von Hugging Face.
/// Empfehlung richtet sich wie auf iOS nach dem Arbeitsspeicher.
/// </summary>
public static class ModelCatalog
{
    public sealed record Model(
        string Id,            // Dateiname im Modell-Ordner
        string Name,          // Anzeigename
        string SizeHint,      // z. B. "466 MB"
        string Note,          // Kurzbeschreibung für die UI
        string DownloadUrl);

    // MARK: Spracherkennung (ggml, mehrsprachig — KEINE .en-Varianten)

    public static readonly Model[] AsrModels =
    {
        new("ggml-base.bin", "Whisper Base", "142 MB",
            "Sehr schnell, mäßige Genauigkeit — für schwache Rechner.",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"),
        new("ggml-small.bin", "Whisper Small", "466 MB",
            "Guter Kompromiss aus Tempo und Genauigkeit.",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"),
        new("ggml-large-v3-turbo.bin", "Whisper Large v3 Turbo", "1,6 GB",
            "Beste Genauigkeit, braucht einen flotten Rechner.",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
    };

    // MARK: Formatierung (GGUF; bewusst NUR Qwen-Familie, damit ein
    // Chat-Template für alle Einträge stimmt — siehe LlmFormatter)

    public static readonly Model[] LlmModels =
    {
        new("qwen2.5-1.5b-instruct-q4_k_m.gguf", "Qwen 2.5 (1,5B)", "1,0 GB",
            "Schnell, für die Textbereinigung völlig ausreichend.",
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"),
        new("qwen2.5-3b-instruct-q4_k_m.gguf", "Qwen 2.5 (3B)", "2,0 GB",
            "Gründlicher, spürbar langsamer — für starke Rechner.",
            "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"),
    };

    // MARK: Empfehlung nach Arbeitsspeicher

    public static Model RecommendedAsr()
    {
        var gb = PhysicalMemoryGB();
        if (gb >= 16) return AsrModels[2];   // large-v3-turbo
        if (gb >= 8) return AsrModels[1];    // small
        return AsrModels[0];                 // base
    }

    public static Model RecommendedLlm()
        => PhysicalMemoryGB() >= 16 ? LlmModels[1] : LlmModels[0];

    public static Model? AsrById(string id) => AsrModels.FirstOrDefault(m => m.Id == id);

    /// <summary>
    /// Erst der feste Katalog, dann die über die Hugging-Face-Liste gewählten
    /// Modelle aus den Einstellungen.
    /// ACHTUNG: nicht aus <c>Settings.Load()</c> heraus aufrufen — dort ist
    /// <c>Settings.Shared</c> noch nicht fertig initialisiert.
    /// </summary>
    public static Model? LlmById(string id)
        => LlmModels.FirstOrDefault(m => m.Id == id)
           ?? Settings.Shared.DiscoveredLlmModels.FirstOrDefault(m => m.Id == id);

    /// <summary>Merkt ein entdecktes Modell, damit es nach dem Neustart auflösbar
    /// bleibt. Mehr als ein Dutzend brauchen wir nicht — die Liste bleibt kurz.</summary>
    public static void Remember(Model model)
    {
        var list = Settings.Shared.DiscoveredLlmModels;
        if (LlmModels.Any(m => m.Id == model.Id)) return;
        list.RemoveAll(m => m.Id == model.Id);
        list.Insert(0, model);
        if (list.Count > 12) list.RemoveRange(12, list.Count - 12);
    }

    public static string PathFor(Model model) => Path.Combine(StoreIO.ModelDirectory, model.Id);
    public static bool IsDownloaded(Model model) => File.Exists(PathFor(model));

    public static int PhysicalMemoryGB()
    {
        try
        {
            // GC-API liefert das physische RAM ohne WMI-Overhead.
            var info = GC.GetGCMemoryInfo();
            return (int)(info.TotalAvailableMemoryBytes / (1024L * 1024 * 1024));
        }
        catch
        {
            return 8;
        }
    }
}

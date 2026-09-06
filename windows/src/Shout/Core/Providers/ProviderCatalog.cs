namespace Shout.Core;

/// <summary>
/// Für welchen Verarbeitungsschritt eine Anbieter-Einstellung gilt. Beide sind
/// getrennt konfigurierbar: Man kann lokal transkribieren und extern aufbereiten
/// — oder Groq fürs Audio und EURouter für den Text nehmen.
/// </summary>
public enum EnginePurpose
{
    Text,
    Audio,
}

/// <summary>
/// Eine mitgelieferte Anbieter-Vorlage. <b>Reine Daten</b> — ein neuer Anbieter ist
/// ein Listeneintrag, kein Code. Genau deshalb reicht ein einziger
/// OpenAI-kompatibler Client für alle.
/// </summary>
/// <param name="BaseUrl">Leer bei „Eigener Endpunkt" — dort trägt der Nutzer sie ein.</param>
/// <param name="KeyUrl">Seite, auf der man den Schlüssel bekommt. Ohne diesen Link sucht man.</param>
/// <param name="ChatModels">Zwei bis drei handverlesene Empfehlungen. Die vollständige,
/// aktuelle Liste holt der „Modelle laden"-Knopf beim Anbieter selbst.</param>
/// <param name="AudioModels">Empfehlungen für die Transkription. Kann leer sein, obwohl
/// der Anbieter Audio kann (siehe <paramref name="CanAudio"/>).</param>
/// <param name="CanAudio">Ob der Anbieter überhaupt transkribieren kann. Getrennt von
/// <paramref name="AudioModels"/>, weil „Eigener Endpunkt" Audio kann, aber keine
/// Modellvorschläge hat — dort weiß nur der Nutzer, was sein Server anbietet.</param>
/// <param name="CanText">Ob der Anbieter Textmodelle anbietet. Es gibt Dienste, die nur
/// transkribieren — die sollen nicht in der Auswahl für die Aufbereitung stehen, wo sie
/// beim ersten Versuch scheitern würden.</param>
/// <param name="NeedsKey">Anbieter auf dem eigenen Rechner brauchen keinen Schlüssel.</param>
/// <param name="Note">Ein Satz Einordnung für die Oberfläche. Bleibt hier deutscher
/// Klartext und wird erst beim Anzeigen durch <c>Loc.T</c> geschickt — wie am Mac.</param>
public sealed record ProviderTemplate(
    string Id,
    string Name,
    string BaseUrl,
    string KeyUrl,
    string[] ChatModels,
    string[] AudioModels,
    bool CanAudio,
    bool CanText,
    bool NeedsKey,
    string Note);

/// <summary>
/// Die mitgelieferten Vorlagen.
///
/// <para><b>Prüfstand der Basis-Adressen: alle am 01.09.2026 gegen die Dokumentation
/// des jeweiligen Anbieters geprüft.</b> Eine falsche Adresse in einer mitgelieferten
/// Vorlage ist schlimmer als keine Vorlage, weil der Fehlschlag dann wie ein Fehler
/// der App aussieht.</para>
///
/// <para>Die Modell-IDs sind Startwerte für die Auswahl und veralten schneller als die
/// Adressen; der „Modelle laden"-Knopf und das freie Modellfeld sind die Notausgänge,
/// wenn eine Vorlage hinterherhängt.</para>
/// </summary>
public static class ProviderCatalog
{
    public static readonly ProviderTemplate[] All =
    {
        new("openai", "OpenAI",
            "https://api.openai.com/v1",
            "https://platform.openai.com/api-keys",
            new[] { "gpt-5-mini", "gpt-5" },
            new[] { "gpt-4o-mini-transcribe", "whisper-1" },
            CanAudio: true, CanText: true, NeedsKey: true,
            "Der Referenz-Endpunkt. Kann Text und Transkription."),

        // Zeitmarken sind bei OpenRouters Transkription nicht dokumentiert. Bleiben
        // sie aus, setzt RemoteSpeechEngine ein Ersatzsegment über die ganze Länge —
        // Diktat und .txt gehen dann, Untertitel nicht.
        new("openrouter", "OpenRouter",
            "https://openrouter.ai/api/v1",
            "https://openrouter.ai/keys",
            new[] { "openai/gpt-5-mini", "anthropic/claude-sonnet-4.5" },
            new[] { "openai/whisper-large-v3", "openai/gpt-4o-mini-transcribe", "google/chirp-3" },
            CanAudio: true, CanText: true, NeedsKey: true,
            "Ein Schlüssel für hunderte Modelle, auch für die Transkription. Dort " +
            "liefert er womöglich keine Zeitmarken; Untertitel können dann " +
            "unbrauchbar werden."),

        new("eurouter", "EURouter",
            "https://api.eurouter.ai/v1",
            "https://www.eurouter.ai",
            new[] { "openai/gpt-oss-120b", "mistral/mistral-large" },
            Array.Empty<string>(),
            CanAudio: false, CanText: true, NeedsKey: true,
            "Verarbeitung ausschließlich in der EU, ein Schlüssel für über 100 " +
            "Modelle. Keine Transkription."),

        new("groq", "Groq",
            "https://api.groq.com/openai/v1",
            "https://console.groq.com/keys",
            new[] { "llama-3.3-70b-versatile" },
            new[] { "whisper-large-v3-turbo", "whisper-large-v3" },
            CanAudio: true, CanText: true, NeedsKey: true,
            "Sehr schnell — die interessanteste Wahl fürs Live-Diktat."),

        // Reiner Transkriptions-Dienst in diesem Katalog: CanText ist false, damit er
        // nicht in der Auswahl für die Aufbereitung auftaucht. Liefert verbose_json
        // mit Segment-Zeitmarken, Untertitel gehen also. Für EU-Verarbeitung die
        // Adresse auf eu-api.lemonfox.ai ändern.
        new("lemonfox", "Lemonfox",
            "https://api.lemonfox.ai/v1",
            "https://www.lemonfox.ai/apis/keys",
            Array.Empty<string>(),
            new[] { "whisper-1" },
            CanAudio: true, CanText: false, NeedsKey: true,
            "Nur Transkription, dafür sehr günstig (rund $0,10 je Stunde) und mit " +
            "Zeitmarken. Für EU-Verarbeitung „api“ in der Adresse durch „eu-api“ " +
            "ersetzen."),

        new("mistral", "Mistral",
            "https://api.mistral.ai/v1",
            "https://console.mistral.ai/api-keys",
            new[] { "mistral-large-latest", "mistral-small-latest" },
            new[] { "voxtral-mini-latest" },
            CanAudio: true, CanText: true, NeedsKey: true,
            "Europäischer Anbieter, kann Text und Transkription."),

        new("deepseek", "DeepSeek",
            "https://api.deepseek.com/v1",
            "https://platform.deepseek.com/api_keys",
            new[] { "deepseek-chat" },
            Array.Empty<string>(),
            CanAudio: false, CanText: true, NeedsKey: true,
            "Günstig. Keine Transkription."),

        // Anthropic bezeichnet diese Schicht in der eigenen Dokumentation ausdrücklich
        // als Weg zum Ausprobieren und Vergleichen, nicht als Dauerlösung. Das gehört
        // an die Vorlage: Wer seinen Arbeitsalltag darauf baut, soll es vorher wissen.
        new("anthropic", "Anthropic",
            "https://api.anthropic.com/v1",
            "https://console.anthropic.com/settings/keys",
            new[] { "claude-sonnet-4.5", "claude-haiku-4.5" },
            Array.Empty<string>(),
            CanAudio: false, CanText: true, NeedsKey: true,
            "Über die OpenAI-Kompatibilitätsschicht, die Anthropic selbst als " +
            "Testweg und nicht als Dauerlösung bezeichnet. Keine Transkription."),

        new("gemini", "Google Gemini",
            "https://generativelanguage.googleapis.com/v1beta/openai",
            "https://aistudio.google.com/apikey",
            new[] { "gemini-2.5-flash", "gemini-2.5-pro" },
            Array.Empty<string>(),
            CanAudio: false, CanText: true, NeedsKey: true,
            "Über die OpenAI-Kompatibilitätsschicht. Keine Transkription."),

        new("xai", "xAI · Grok",
            "https://api.x.ai/v1",
            "https://console.x.ai",
            new[] { "grok-4", "grok-4-fast" },
            Array.Empty<string>(),
            CanAudio: false, CanText: true, NeedsKey: true,
            "Schlüssel aus der xAI-Konsole. Ein SuperGrok-Abo gilt hier NICHT — " +
            "Abos enthalten keinen API-Zugang."),

        new("ollama", "Ollama",
            "http://localhost:11434/v1",
            "https://ollama.com/download",
            new[] { "gemma3:12b", "qwen3:14b" },
            Array.Empty<string>(),
            CanAudio: false, CanText: true, NeedsKey: false,
            "Läuft auf deinem eigenen Rechner — auch auf einem anderen im eigenen " +
            "Netz. Dann verlässt nichts dein Netzwerk."),

        new("lmstudio", "LM Studio",
            "http://localhost:1234/v1",
            "https://lmstudio.ai",
            Array.Empty<string>(),
            Array.Empty<string>(),
            CanAudio: false, CanText: true, NeedsKey: false,
            "Wie Ollama: dein eigener Rechner, dein eigenes Netz."),

        new("custom", "Eigener Endpunkt",
            "",
            "",
            Array.Empty<string>(),
            Array.Empty<string>(),
            CanAudio: true, CanText: true, NeedsKey: true,
            "Alles selbst eintragen — für whisper.cpp-Server, vLLM, Pauschal-Abos " +
            "mit eigenem Endpunkt und alles andere OpenAI-kompatible."),
    };

    public static ProviderTemplate? Template(string id)
        => All.FirstOrDefault(t => t.Id == id);

    /// <summary>Vorlagen, die den gewünschten Schritt überhaupt können.</summary>
    public static ProviderTemplate[] Templates(EnginePurpose purpose)
        => purpose == EnginePurpose.Text
            ? All.Where(t => t.CanText).ToArray()
            : All.Where(t => t.CanAudio).ToArray();
}

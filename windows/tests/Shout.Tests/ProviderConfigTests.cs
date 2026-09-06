using Shout.Core;
using Xunit;

namespace Shout.Tests;

/// <summary>
/// Adressbau und Engine-Wahl. Beides läuft über direkt gebaute Objekte und einen
/// hereingereichten Schlüssel-Delegaten: <c>Settings.Shared</c> würde beim ersten
/// Zugriff settings.json anlegen, und ein Test hat auf der Platte nichts verloren.
/// </summary>
public class ProviderConfigTests
{
    private static RemoteConfig Config(string baseUrl, string templateId = "custom")
        => new(templateId, baseUrl, "irgendein-modell");

    [Fact]
    public void NurHostBekommtV1()
    {
        Assert.Equal("https://api.example.com/v1/chat/completions",
                     Config("https://api.example.com").ChatUrl);
    }

    [Fact]
    public void SchraegstricheUndLeerzeichenFliegenRaus()
    {
        Assert.Equal("https://api.example.com/v1/models",
                     Config("  https://api.example.com/v1///  ").ModelsUrl);
    }

    /// <summary>Wer die Chat-Adresse einträgt, soll trotzdem transkribieren können.</summary>
    [Fact]
    public void GanzerEndpunktErgibtDieAndereAdresse()
    {
        var config = Config("https://api.openai.com/v1/chat/completions");
        Assert.Equal("https://api.openai.com/v1/audio/transcriptions", config.AudioUrl);
        Assert.Equal("https://api.openai.com/v1/chat/completions", config.ChatUrl);
    }

    /// <summary>Google liegt unter /v1beta/openai — daran darf nichts „korrigiert" werden.</summary>
    [Fact]
    public void FremderPfadBleibtStehen()
    {
        var config = Config("https://generativelanguage.googleapis.com/v1beta/openai");
        Assert.Equal("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                     config.ChatUrl);
    }

    [Fact]
    public void PortBleibtErhalten()
    {
        Assert.Equal("http://localhost:11434/v1/chat/completions",
                     Config("http://localhost:11434").ChatUrl);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("api.example.com")]
    [InlineData("localhost:1234")]
    [InlineData("ftp://api.example.com")]
    public void UnbrauchbareAdresseErgibtNichts(string baseUrl)
    {
        var config = Config(baseUrl);
        Assert.Null(config.ChatUrl);
        Assert.Null(config.AudioUrl);
        Assert.Null(config.ModelsUrl);
    }

    [Fact]
    public void VorlageSetztErstesModell()
    {
        var vorlage = ProviderCatalog.Template("openai")!;
        Assert.Equal("gpt-5-mini", new RemoteConfig(vorlage, EnginePurpose.Text).Model);
        Assert.Equal("gpt-4o-mini-transcribe", new RemoteConfig(vorlage, EnginePurpose.Audio).Model);
    }

    // MARK: Katalog

    [Fact]
    public void KatalogTrenntTextUndAudio()
    {
        Assert.Equal(13, ProviderCatalog.All.Length);
        Assert.DoesNotContain(ProviderCatalog.Templates(EnginePurpose.Text),
                              t => t.Id == "lemonfox");
        Assert.DoesNotContain(ProviderCatalog.Templates(EnginePurpose.Audio),
                              t => t.Id == "deepseek");
        Assert.Contains(ProviderCatalog.Templates(EnginePurpose.Audio), t => t.Id == "lemonfox");
        Assert.Null(ProviderCatalog.Template("gibtesnicht"));
    }

    // MARK: Engine-Wahl

    private static RemoteConfig OpenAi() => new("openai", "https://api.openai.com/v1", "gpt-5-mini");

    [Fact]
    public void MitSchluesselWirdDerAnbieterGenommen()
    {
        var wahl = EngineSelection.Decide(EnginePurpose.Text, "remote", OpenAi(), _ => true);
        Assert.True(wahl.IsRemote);
        Assert.Equal("openai", wahl.Template!.Id);
        Assert.Equal("gpt-5-mini", wahl.Config!.Model);
    }

    /// <summary>Der wichtigste Fall: Ein importierter Sicherungsstand bringt die
    /// Konfiguration mit, den Schlüssel aber nicht.</summary>
    [Fact]
    public void OhneSchluesselWirdLokalGearbeitet()
    {
        var wahl = EngineSelection.Decide(EnginePurpose.Text, "remote", OpenAi(), _ => false);
        Assert.False(wahl.IsRemote);
    }

    [Fact]
    public void AnbieterOhneTranskriptionFaelltAufLokalZurueck()
    {
        var config = new RemoteConfig("deepseek", "https://api.deepseek.com/v1", "deepseek-chat");
        Assert.False(EngineSelection.Decide(EnginePurpose.Audio, "remote", config, _ => true).IsRemote);
        Assert.True(EngineSelection.Decide(EnginePurpose.Text, "remote", config, _ => true).IsRemote);
    }

    [Fact]
    public void EinstellungLokalSchlaegtAlles()
    {
        Assert.False(EngineSelection.Decide(EnginePurpose.Text, "local", OpenAi(), _ => true).IsRemote);
        Assert.False(EngineSelection.Decide(EnginePurpose.Text, "remote", null, _ => true).IsRemote);
    }

    [Fact]
    public void UnbrauchbareAdresseFaelltAufLokalZurueck()
    {
        var config = new RemoteConfig("custom", "api.example.com", "modell");
        Assert.False(EngineSelection.Decide(EnginePurpose.Text, "remote", config, _ => true).IsRemote);
    }

    /// <summary>Ollama läuft auf dem eigenen Rechner und braucht keinen Schlüssel.</summary>
    [Fact]
    public void EigenerRechnerBrauchtKeinenSchluessel()
    {
        var config = new RemoteConfig("ollama", "http://localhost:11434/v1", "qwen3:14b");
        Assert.True(EngineSelection.Decide(EnginePurpose.Text, "remote", config, _ => false).IsRemote);
    }
}

using Shout.Core;
using Xunit;

namespace Shout.Tests;

/// <summary>Die Fallunterscheidung der Antworten — jeder Fall braucht eine andere Abhilfe.</summary>
public class RemoteHttpTests
{
    private static RemoteProviderException Fehler(int status, string body = "{}")
    {
        return Assert.Throws<RemoteProviderException>(
            () => RemoteHttp.Check(status, body, model: "gpt-5-mini"));
    }

    [Theory]
    [InlineData(200)]
    [InlineData(201)]
    [InlineData(299)]
    public void ErfolgWirftNicht(int status)
    {
        RemoteHttp.Check(status, "{}", model: "gpt-5-mini");
    }

    [Theory]
    [InlineData(401)]
    [InlineData(403)]
    public void AbgelehnterSchluessel(int status)
    {
        Assert.Equal(RemoteFailure.Unauthorized, Fehler(status).Failure);
    }

    [Fact]
    public void KeinGuthaben()
    {
        Assert.Equal(RemoteFailure.NoCredit, Fehler(402).Failure);
    }

    /// <summary>Mit Modellhinweis ist es ein veraltetes Modell — der häufigste Fall,
    /// wenn eine Vorlage hinterherhängt.</summary>
    [Fact]
    public void VierNullVierMitModellhinweis()
    {
        var fehler = Fehler(404, """{"error":{"message":"The model `gpt-4.7` does not exist"}}""");
        Assert.Equal(RemoteFailure.UnknownModel, fehler.Failure);
        Assert.Equal("gpt-5-mini", fehler.Model);
        Assert.False(fehler.IsTransient);
    }

    /// <summary>Ohne Hinweis ist die Adresse falsch — und ein zweiter Versuch hilft nicht.</summary>
    [Fact]
    public void VierNullVierOhneModellhinweis()
    {
        var fehler = Fehler(404, """{"error":{"message":"Not found"}}""");
        Assert.Equal(RemoteFailure.Http, fehler.Failure);
        Assert.Equal(404, fehler.Status);

        Assert.Equal(RemoteFailure.Http, Fehler(404, "<html>nope</html>").Failure);
    }

    [Fact]
    public void Ratenlimit()
    {
        var fehler = Fehler(429);
        Assert.Equal(RemoteFailure.RateLimited, fehler.Failure);
        Assert.True(fehler.IsTransient);
    }

    /// <summary>Serverfehler gehen von selbst weg, ein abgelehnter Schlüssel nicht.</summary>
    [Fact]
    public void ServerfehlerIstVoruebergehend()
    {
        var fehler = Fehler(500);
        Assert.Equal(RemoteFailure.Http, fehler.Failure);
        Assert.Equal(500, fehler.Status);
        Assert.True(fehler.IsTransient);
    }

    [Fact]
    public void MeldungWirdNurZurFallunterscheidungGelesen()
    {
        Assert.Equal("kaputt", RemoteHttp.MessageFrom("""{"error":{"message":"kaputt"}}"""));
        Assert.Equal("kaputt", RemoteHttp.MessageFrom("""{"message":"kaputt"}"""));
        Assert.Equal("", RemoteHttp.MessageFrom("kein json"));
        Assert.Equal("", RemoteHttp.MessageFrom(""));
    }

    [Fact]
    public void VerbrauchKommtAusDerAntwort()
    {
        using var doc = System.Text.Json.JsonDocument.Parse(
            """{"usage":{"prompt_tokens":12,"completion_tokens":30}}""");
        var usage = RemoteHttp.UsageFrom(doc.RootElement);

        Assert.NotNull(usage);
        Assert.Equal(12, usage!.Value.Prompt);
        Assert.Equal(42, usage.Value.Total);

        using var ohne = System.Text.Json.JsonDocument.Parse("""{"usage":{}}""");
        Assert.Null(RemoteHttp.UsageFrom(ohne.RootElement));
    }

    /// <summary>Zeitgrenze und „gar keine Verbindung" brauchen verschiedene Abhilfen.</summary>
    [Fact]
    public void NetzfehlerWerdenUnterschieden()
    {
        Assert.Equal(RemoteFailure.TimedOut,
                     RemoteHttp.Translate(new TaskCanceledException()).Failure);
        Assert.Equal(RemoteFailure.CannotConnect,
                     RemoteHttp.Translate(new HttpRequestException("weg")).Failure);
        Assert.Equal(RemoteFailure.MalformedResponse,
                     RemoteHttp.Translate(new InvalidOperationException()).Failure);

        var bekannt = new RemoteProviderException(RemoteFailure.NoCredit);
        Assert.Same(bekannt, RemoteHttp.Translate(bekannt));
    }
}

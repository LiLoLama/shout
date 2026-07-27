using System.Reflection;
using Velopack;
using Velopack.Sources;

namespace Shout.Core;

/// <summary>
/// Automatische Aktualisierung über Velopack gegen die GitHub-Releases — das
/// Windows-Pendant zu Sparkle in der Mac-App.
///
/// Funktioniert nur in einer per Setup.exe installierten Kopie: dort verwaltet
/// Velopack die Versionsordner unter %LOCALAPPDATA%\shout. Läuft die App direkt
/// aus einem Build-Ordner, meldet <see cref="IsSupported"/> false und die
/// Oberfläche weist darauf hin, statt einen Fehler zu zeigen.
/// </summary>
public sealed class Updater
{
    private const string RepoUrl = "https://github.com/LiLoLama/shout";

    public enum State
    {
        /// <summary>Noch nicht gesucht.</summary>
        Unknown,
        /// <summary>Nicht über den Installer installiert — kein Auto-Update möglich.</summary>
        Unsupported,
        Checking,
        UpToDate,
        Available,
        Downloading,
        /// <summary>Fertig heruntergeladen; wird beim Neustart übernommen.</summary>
        ReadyToRestart,
        Failed,
    }

    private readonly UpdateManager? manager;
    private UpdateInfo? pending;

    /// <summary>Zustand hat sich geändert (für Tray-Menü und Einstellungen).</summary>
    public event Action? Changed;

    public State Status { get; private set; } = State.Unknown;
    /// <summary>Fortschritt des Downloads in Prozent (nur im Zustand Downloading).</summary>
    public int Progress { get; private set; }
    /// <summary>Version der gefundenen Aktualisierung.</summary>
    public string? AvailableVersion { get; private set; }
    /// <summary>Meldung im Fehlerfall.</summary>
    public string? Error { get; private set; }

    public Updater()
    {
        try
        {
            manager = new UpdateManager(new GithubSource(RepoUrl, null, prerelease: false));
        }
        catch (Exception ex)
        {
            Error = ex.Message;
        }
        Status = IsSupported ? State.Unknown : State.Unsupported;
    }

    /// <summary>Läuft diese Kopie in einer von Velopack verwalteten Installation?</summary>
    public bool IsSupported => manager?.IsInstalled == true;

    /// <summary>Laufende Programmversion — installiert oder aus dem Build-Ordner.</summary>
    public string CurrentVersion
    {
        get
        {
            if (manager?.CurrentVersion is { } v) return v.ToString();
            var informational = Assembly.GetEntryAssembly()
                ?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            // Der Informational-Version hängt oft "+<commit>" an — abschneiden.
            if (informational is { Length: > 0 })
                return informational.Split('+')[0];
            return Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "unbekannt";
        }
    }

    /// <summary>Sucht nach einer neueren Version. Fehler landen im Zustand, nicht als Ausnahme.</summary>
    public async Task CheckAsync()
    {
        if (manager == null || !IsSupported)
        {
            Set(State.Unsupported);
            return;
        }
        if (Status is State.Checking or State.Downloading) return;

        Set(State.Checking);
        try
        {
            pending = await manager.CheckForUpdatesAsync();
            if (pending == null)
            {
                Set(State.UpToDate);
                return;
            }
            AvailableVersion = pending.TargetFullRelease.Version.ToString();
            Set(State.Available);
        }
        catch (Exception ex)
        {
            Error = ex.Message;
            Set(State.Failed);
        }
    }

    /// <summary>Lädt die gefundene Aktualisierung herunter; übernommen wird sie beim Neustart.</summary>
    public async Task DownloadAsync()
    {
        if (manager == null || pending == null) return;
        Set(State.Downloading);
        Progress = 0;
        try
        {
            await manager.DownloadUpdatesAsync(pending, percent =>
            {
                Progress = percent;
                Changed?.Invoke();
            });
            Set(State.ReadyToRestart);
        }
        catch (Exception ex)
        {
            Error = ex.Message;
            Set(State.Failed);
        }
    }

    /// <summary>Beendet die App und startet sie in der neuen Version neu.</summary>
    public void ApplyAndRestart()
    {
        if (manager == null || pending == null) return;
        manager.ApplyUpdatesAndRestart(pending);
    }

    /// <summary>Sucht im Hintergrund und lädt gleich herunter (stiller Start-Check
    /// wie Sparkle am Mac). Der Nutzer wird erst beim fertigen Download informiert.</summary>
    public async Task CheckAndDownloadAsync()
    {
        await CheckAsync();
        if (Status == State.Available) await DownloadAsync();
    }

    /// <summary>Kurze Beschreibung des Zustands für die Oberfläche.</summary>
    public string StatusText => Status switch
    {
        State.Unsupported =>
            "Automatische Aktualisierung steht nur in der installierten Version zur Verfügung "
            + "(Setup.exe von der Releases-Seite). Diese Kopie läuft aus einem Programmordner.",
        State.Checking => "Suche nach Aktualisierungen …",
        State.UpToDate => "shout. ist aktuell.",
        State.Available => $"Version {AvailableVersion} ist verfügbar.",
        State.Downloading => $"Wird geladen … {Progress} %",
        State.ReadyToRestart => $"Version {AvailableVersion} ist bereit — beim Neustart wird sie übernommen.",
        State.Failed => $"Aktualisierung fehlgeschlagen: {Error}",
        _ => "Noch nicht nach Aktualisierungen gesucht.",
    };

    private void Set(State next)
    {
        Status = next;
        Changed?.Invoke();
    }
}

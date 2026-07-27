# Erzeugt das Windows-Release: Setup.exe zum Herunterladen plus den Feed, aus dem
# sich installierte Kopien selbst aktualisieren (Velopack — Windows-Pendant zu
# Sparkle am Mac).
#
#   powershell -ExecutionPolicy Bypass -File release.ps1            # Version aus der csproj
#   powershell -ExecutionPolicy Bypass -File release.ps1 -Version 1.0.1
#
# Voraussetzungen: .NET 8 SDK und das Velopack-Werkzeug
#   dotnet tool install -g vpk --version 1.2.0
#
# Ergebnis in windows/release/:
#   shout-win-Setup.exe        ← das lädt man von GitHub herunter
#   shout-win-<version>-full.nupkg
#   releases.win.json          ← Feed für die Aktualisierung; MUSS mit ins Release
#
# Danach als GitHub-Release veröffentlichen (Tag „windows-v<version>"), z. B.:
#   gh release create windows-v1.0.0 release/* --title "shout. 1.0.0 für Windows"
# Der GitHub-Workflow .github/workflows/windows-release.yml macht genau das
# automatisch, sobald ein solcher Tag gepusht wird.

param(
    [string]$Version = "",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$project = "src/Shout/Shout.csproj"
$publishDir = "src/Shout/bin/$Configuration/net8.0-windows/publish"
$outputDir = "release"

# Version aus der csproj lesen, wenn keine übergeben wurde.
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = ([xml](Get-Content $project)).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($Version)) { throw "Version nicht gefunden — bitte -Version angeben." }
Write-Host "shout. $Version für Windows wird gebaut …" -ForegroundColor Cyan

# Alte Ausgaben entfernen, damit nichts von einem früheren Lauf mitwandert.
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
New-Item -ItemType Directory -Force $outputDir | Out-Null

# Bewusst framework-abhängig und OHNE PublishSingleFile: das LLamaSharp-CPU-Backend
# braucht seine AVX-Varianten als Unterordner unter runtimes/ (siehe README).
dotnet publish $project -c $Configuration -p:Version=$Version --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet publish fehlgeschlagen." }

# Setup.exe + Update-Feed schnüren. --framework lässt das Setup die .NET-8-Desktop-
# Runtime nachinstallieren, falls sie auf dem Zielrechner fehlt.
vpk pack `
    --packId shout `
    --packVersion $Version `
    --packDir $publishDir `
    --mainExe shout.exe `
    --packTitle "shout." `
    --packAuthors "inthezone" `
    --icon assets/shout.ico `
    --framework net8-x64-desktop `
    --shortcuts Desktop,StartMenuRoot `
    --outputDir $outputDir
if ($LASTEXITCODE -ne 0) { throw "vpk pack fehlgeschlagen." }

Write-Host "`nFertig — in $outputDir/:" -ForegroundColor Green
Get-ChildItem $outputDir | ForEach-Object {
    "  {0,-42} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB)
}
Write-Host @"

Nächster Schritt: als GitHub-Release veröffentlichen (ALLE Dateien aus $outputDir/,
releases.win.json ist für die Auto-Aktualisierung zwingend):

  git tag windows-v$Version
  git push origin windows-v$Version

Der Workflow baut und veröffentlicht dann selbst. Manuell wäre es:

  gh release create windows-v$Version $outputDir/* --title "shout. $Version für Windows"
"@ -ForegroundColor Yellow

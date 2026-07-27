# Erzeugt windows/assets/shout.ico aus dem echten App-Logo, das auch die Mac- und
# iOS-Version nutzen (Resources/Assets.xcassets/AppIcon.appiconset) — damit es nur
# EINE Quelle für das Logo gibt.
#
#   powershell -ExecutionPolicy Bypass -File make-icon.ps1
#
# Muss nur erneut laufen, wenn sich das Logo ändert (shout.ico ist eingecheckt).
Add-Type -AssemblyName System.Drawing

$iconSet = Join-Path $PSScriptRoot "..\..\Resources\Assets.xcassets\AppIcon.appiconset"
if (-not (Test-Path $iconSet)) { throw "Logo-Ordner nicht gefunden: $iconSet" }

# Windows nutzt diese Kantenlängen. Wo eine passgenaue Vorlage existiert, wird sie
# direkt genommen (die kleinen sind von Hand optimiert); der Rest wird aus der
# größten Vorlage herunterskaliert.
$sizes = @(16, 20, 24, 32, 48, 64, 128, 256)
$source = @{}
foreach ($s in @(16, 32, 64, 128, 256, 512, 1024)) {
    $p = Join-Path $iconSet "icon_$s.png"
    if (Test-Path $p) { $source[$s] = $p }
}
$largest = ($source.Keys | Sort-Object -Descending)[0]
Write-Output "Vorlagen: $(($source.Keys | Sort-Object) -join ', ') — größte: $largest"

# Unterhalb dieser Kantenlänge verschmelzen die feinen Balken des Original-Logos
# zu einem Klecks (das gilt auch für Apples handoptimiertes 16-px-Asset). Für
# Titelleiste, Taskleiste und Infobereich wird daher eine vereinfachte, gut
# lesbare Waveform gezeichnet — dieselbe Bildsprache wie die Aufnahme-Pille.
# Die Schwelle liegt bei 48, weil Windows die Titelleiste (16 px) aus der
# 32-px-Ebene herunterrechnet: die muss also schon die einfache Fassung sein.
$smallThreshold = 48

function New-SmallLogo([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Dunkles, abgerundetes Quadrat wie im Original.
    $radius = [Math]::Max(2.0, $size * 0.22)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($size - $d, 0, $d, $d, 270, 90)
    $path.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
    $path.AddArc(0, $size - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $back = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 32, 32, 36))
    $g.FillPath($back, $path)
    $back.Dispose()

    # Fünf Balken, symmetrisch — Höhen wie in der Pille gewichtet.
    $weights = @(0.42, 0.68, 1.0, 0.68, 0.42)
    $barWidth = [Math]::Max(1.0, [Math]::Round($size * 0.11))
    $gap = [Math]::Max(1.0, [Math]::Round($size * 0.07))
    $totalWidth = $weights.Count * $barWidth + ($weights.Count - 1) * $gap
    $x = ($size - $totalWidth) / 2.0
    $maxHeight = $size * 0.62
    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 74, 10))
    foreach ($weight in $weights) {
        $h = [Math]::Max(2.0, $maxHeight * $weight)
        $g.FillRectangle($accent, [float]$x, [float](($size - $h) / 2.0), [float]$barWidth, [float]$h)
        $x += $barWidth + $gap
    }
    $accent.Dispose(); $path.Dispose(); $g.Dispose()

    $stream = New-Object System.IO.MemoryStream
    $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $bytes = $stream.ToArray()
    $stream.Dispose()
    # Ausdrücklich als Byte-Feld und ohne Aufzählung zurückgeben.
    return ,[byte[]]$bytes
}

$pngs = @()
foreach ($size in $sizes) {
    if ($size -lt $smallThreshold) {
        $bytes = New-SmallLogo $size
    } elseif ($source.ContainsKey($size)) {
        # Passgenaue Vorlage unverändert übernehmen.
        $bytes = [System.IO.File]::ReadAllBytes($source[$size])
    } else {
        $src = [System.Drawing.Image]::FromFile($source[$largest])
        $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
        $g.Dispose(); $src.Dispose()
        $stream = New-Object System.IO.MemoryStream
        $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $bytes = $stream.ToArray()
        $stream.Dispose()
    }
    $pngs += ,@{ Size = $size; Bytes = $bytes }
}

# ICO-Container: Kopf (6 Byte) + je Bild ein 16-Byte-Verzeichniseintrag, dann die
# PNG-Daten. PNG-Einträge sind ab Windows Vista erlaubt.
$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($out)
$w.Write([UInt16]0)                 # reserviert
$w.Write([UInt16]1)                 # Typ 1 = Icon
$w.Write([UInt16]$pngs.Count)

$offset = 6 + 16 * $pngs.Count
foreach ($png in $pngs) {
    $dim = if ($png.Size -ge 256) { 0 } else { $png.Size }   # 256 wird als 0 kodiert
    $w.Write([Byte]$dim)            # Breite
    $w.Write([Byte]$dim)            # Höhe
    $w.Write([Byte]0)               # Palettengröße (0 = keine)
    $w.Write([Byte]0)               # reserviert
    $w.Write([UInt16]1)             # Farbebenen
    $w.Write([UInt16]32)            # Bits pro Pixel
    $w.Write([UInt32]$png.Bytes.Length)
    $w.Write([UInt32]$offset)
    $offset += $png.Bytes.Length
}
$w.Flush()
# Nutzdaten direkt in den Stream schreiben: bei $w.Write($bytes) wählt PowerShell
# unter Umständen die char[]-Überladung des BinaryWriters und verstümmelt die
# Bilddaten. Write(byte[], int, int) ist eindeutig.
foreach ($png in $pngs) {
    $payload = [byte[]]$png.Bytes
    $out.Write($payload, 0, $payload.Length)
}
$out.Flush()

$target = Join-Path $PSScriptRoot "shout.ico"
[System.IO.File]::WriteAllBytes($target, $out.ToArray())
$w.Dispose(); $out.Dispose()
Write-Output "geschrieben: $target ($([Math]::Round((Get-Item $target).Length / 1KB, 1)) KB, $($pngs.Count) Größen)"

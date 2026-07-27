# Erzeugt windows/assets/shout.ico — derselbe orange Ring wie das Tray-Icon,
# in allen von Windows genutzten Größen. Muss nur erneut laufen, wenn sich das
# Motiv ändert (die Datei ist eingecheckt).
#
#   powershell -ExecutionPolicy Bypass -File make-icon.ps1
Add-Type -AssemblyName System.Drawing

$sizes = @(16, 20, 24, 32, 48, 64, 128, 256)
$accent = [System.Drawing.Color]::FromArgb(255, 255, 74, 10)
$pngs = @()

foreach ($size in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Ringstärke und Einzug proportional wie im Tray-Icon (5/32 bzw. 5/32).
    $inset = [Math]::Max(1.0, $size * 5.0 / 32.0)
    $thickness = [Math]::Max(1.5, $size * 5.0 / 32.0)
    $pen = New-Object System.Drawing.Pen($accent, $thickness)
    $d = $size - 2 * $inset
    $g.DrawEllipse($pen, $inset, $inset, $d, $d)
    $pen.Dispose()
    $g.Dispose()

    $stream = New-Object System.IO.MemoryStream
    $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $pngs += ,@{ Size = $size; Bytes = $stream.ToArray() }
    $stream.Dispose()
}

# ICO-Container schreiben: Kopf (6 Byte) + je Bild ein 16-Byte-Verzeichniseintrag,
# danach die PNG-Daten. PNG-Einträge sind ab Windows Vista erlaubt.
$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($out)
$w.Write([UInt16]0)                 # reserviert
$w.Write([UInt16]1)                 # Typ 1 = Icon
$w.Write([UInt16]$pngs.Count)

$offset = 6 + 16 * $pngs.Count
foreach ($png in $pngs) {
    # 256 wird als 0 kodiert
    $dim = if ($png.Size -ge 256) { 0 } else { $png.Size }
    $w.Write([Byte]$dim)            # Breite
    $w.Write([Byte]$dim)            # Höhe
    $w.Write([Byte]0)               # Farben in der Palette (0 = keine)
    $w.Write([Byte]0)               # reserviert
    $w.Write([UInt16]1)             # Farbebenen
    $w.Write([UInt16]32)            # Bits pro Pixel
    $w.Write([UInt32]$png.Bytes.Length)
    $w.Write([UInt32]$offset)
    $offset += $png.Bytes.Length
}
foreach ($png in $pngs) { $w.Write($png.Bytes) }
$w.Flush()

$target = Join-Path $PSScriptRoot "shout.ico"
[System.IO.File]::WriteAllBytes($target, $out.ToArray())
$w.Dispose(); $out.Dispose()
Write-Output "geschrieben: $target ($([Math]::Round((Get-Item $target).Length / 1KB, 1)) KB, $($pngs.Count) Größen)"

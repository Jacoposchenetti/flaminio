# Crea Flaminio_per_amici.zip sul Desktop: il gioco più una copia di Godot, pronto da scompattare e lanciare.
# Uso (dalla cartella del progetto): powershell -ExecutionPolicy Bypass -File tools\make_package.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godotExe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7*_win64.exe" |
    Where-Object Name -notlike "*console*" | Select-Object -First 1
if (-not $godotExe) { throw "Godot 4.7 non trovato" }

$stage = Join-Path $env:TEMP "flaminio_pkg"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$game = Join-Path $stage "Flaminio\gioco"
New-Item -ItemType Directory -Force $game, (Join-Path $stage "Flaminio\godot") | Out-Null

Copy-Item $godotExe.FullName (Join-Path $stage "Flaminio\godot\Godot.exe")
# File del gioco + manifest.json con la versione (tools/versione.txt): serve al pulsante "Aggiorna" del menu.
$version = (Get-Content (Join-Path $PSScriptRoot "versione.txt") -Raw).Trim()
python -I (Join-Path $PSScriptRoot "stage.py") $game $version
if ($LASTEXITCODE -ne 0) { throw "stage.py non riuscito" }

@"
@echo off
cd /d "%~dp0"
start "" "godot\Godot.exe" --path gioco
"@ | Set-Content -Encoding ascii (Join-Path $stage "Flaminio\Gioca.bat")

# Istruzioni per gli amici: tools\LEGGIMI.txt (si aggiorna lì).
Copy-Item (Join-Path $PSScriptRoot "LEGGIMI.txt") (Join-Path $stage "Flaminio\LEGGIMI.txt")

$zip = Join-Path ([Environment]::GetFolderPath("Desktop")) "Flaminio_per_amici.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage "Flaminio") -DestinationPath $zip -CompressionLevel Optimal
Remove-Item -Recurse -Force $stage
"Creato $zip ({0:N0} MB)" -f ((Get-Item $zip).Length / 1MB)

# Gera a versão para download do os!strike:
#   dist/os!strike/            -> pasta do jogo (o .exe + maps, skins e sounds ao lado)
#   dist/os!strike-<versão>-windows.zip
# Precisa do Godot 4.7.2 e dos export templates 4.7.2 instalados.
# Uso:  powershell -ExecutionPolicy Bypass -File tools\build_release.ps1

param(
	[string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64_console.exe",
	[string]$Version = "1.0"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$out = Join-Path $dist "os!strike"

if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }
$templates = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable"
if (-not (Test-Path (Join-Path $templates "windows_release_x86_64.exe"))) {
	throw "Export templates 4.7.2 not installed in $templates"
}

# Pasta limpa (o Godot ignora a pasta dist).
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
if (-not (Test-Path (Join-Path $dist ".gdignore"))) { New-Item -ItemType File (Join-Path $dist ".gdignore") | Out-Null }

# 1. Executável (com o .pck lá dentro).
Write-Host "Exporting..."
& $Godot --headless --path $root --export-release "Windows Desktop" (Join-Path $out "os!strike.exe")
if (-not (Test-Path (Join-Path $out "os!strike.exe"))) { throw "Export failed" }

# 2. Mapas e skins por defeito (já extraídos e indexados; sem os .osz/.osk repetidos).
function Copy-Content($from, $to, $skipExt) {
	New-Item -ItemType Directory -Force $to | Out-Null
	Get-ChildItem $from -Directory | ForEach-Object {
		Copy-Item -Recurse -Force $_.FullName (Join-Path $to $_.Name)
	}
	Get-ChildItem $from -File | Where-Object { $_.Name -ne ".gdignore" -and $skipExt -notcontains $_.Extension.ToLower() } |
		ForEach-Object { Copy-Item -Force $_.FullName $to }
}
Write-Host "Copying maps, skins and sounds..."
Copy-Content (Join-Path $root "maps") (Join-Path $out "maps") @(".osz", ".txt")
Copy-Content (Join-Path $root "skins") (Join-Path $out "skins") @(".osk")
Copy-Content (Join-Path $root "sounds") (Join-Path $out "sounds") @()
Copy-Item -Force (Join-Path $root "tools\release\README.txt") $out
Copy-Item -Force (Join-Path $root "tools\release\maps_README.txt") (Join-Path $out "maps\README.txt")
Copy-Item -Force (Join-Path $root "tools\release\skins_README.txt") (Join-Path $out "skins\README.txt")
Copy-Item -Force (Join-Path $root "tools\release\sounds_README.txt") (Join-Path $out "sounds\README.txt")

# 3. Zip para download.
$zip = Join-Path $dist "os!strike-$Version-windows.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Write-Host "Zipping..."
Compress-Archive -Path $out -DestinationPath $zip -CompressionLevel Optimal

$size = (Get-Item $zip).Length / 1MB
Write-Host ("Done: {0} ({1:N0} MB)" -f $zip, $size)

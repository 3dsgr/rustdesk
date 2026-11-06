# Repackage the base Windows build as a custom client: portable/self-installing
# .exe plus .msi.
#
# The client reads custom.txt from its executable's directory and loads logos from
# data/flutter_assets/assets at runtime, so no recompilation of the client itself is
# needed. Only the small portable packer (libs/portable) is compiled, because it
# embeds the payload and its own icon.
param(
  [Parameter(Mandatory)][string]$Target,   # windows-x86_64 | windows-aarch64
  [Parameter(Mandatory)][string]$Bundle,   # unzipped bundle.zip
  [Parameter(Mandatory)][string]$BaseZip,  # base-windows-<arch>.zip
  [Parameter(Mandatory)][string]$Source,   # fork checkout at the base tag
  [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Native([scriptblock]$Cmd) {
  & $Cmd
  if ($LASTEXITCODE -ne 0) { throw "command failed ($LASTEXITCODE): $Cmd" }
}

$Bundle = (Resolve-Path $Bundle).Path
$Source = (Resolve-Path $Source).Path
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path

$manifest = Get-Content (Join-Path $Bundle 'manifest.json') -Raw | ConvertFrom-Json
$appName = if ($manifest.app_name) { [string]$manifest.app_name } else { 'RustDesk' }
$fileName = [string]$manifest.file_name
$connType = [string]$manifest.conn_type
$manufacturer = if ($manifest.manufacturer) { [string]$manifest.manufacturer } else { $appName }

# --- assemble the distribution directory ---------------------------------------
$dist = Join-Path $Source 'cc-dist'
Expand-Archive -Path $BaseZip -DestinationPath $dist
if (-not (Test-Path (Join-Path $dist 'rustdesk.exe'))) { throw 'rustdesk.exe not found in base package' }

Copy-Item (Join-Path $Bundle 'custom.txt') (Join-Path $dist 'custom.txt')

$assets = Join-Path $dist 'data/flutter_assets/assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
foreach ($f in 'icon.ico', 'icon.png', 'logo.png', 'logo_light.png', 'logo_dark.png') {
  $p = Join-Path $Bundle $f
  if (Test-Path $p) { Copy-Item $p (Join-Path $assets $f) -Force }
}

# MSI preprocessing locates the app as "<app-name>.exe", so the executable carries
# the app name, as in upstream's own template build.
$exeName = "$appName.exe"
if ($exeName -ne 'rustdesk.exe') {
  Rename-Item (Join-Path $dist 'rustdesk.exe') $exeName
}
$exePath = Join-Path $dist $exeName

$ico = Join-Path $Bundle 'icon.ico'
if (Test-Path $ico) {
  # rcedit (electron/rcedit, MIT) swaps the icon resource in the executable.
  $rcedit = Join-Path $env:RUNNER_TEMP 'rcedit.exe'
  Invoke-WebRequest 'https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe' -OutFile $rcedit
  Invoke-Native { & $rcedit $exePath --set-icon $ico }
  # The portable packer embeds res/icon.ico at compile time (libs/portable/build.rs).
  Copy-Item $ico (Join-Path $Source 'res/icon.ico') -Force
}

# --- portable / self-installing executable --------------------------------------
Push-Location (Join-Path $Source 'libs/portable')
try {
  Invoke-Native { python -m pip install -q -r requirements.txt }
  Invoke-Native { python generate.py -f "$dist/" -o . -e $exePath }
} finally { Pop-Location }
Move-Item (Join-Path $Source 'target/release/rustdesk-portable-packer.exe') (Join-Path $Out "$fileName-$Target.exe")

# --- MSI ---------------------------------------------------------------------------
Push-Location (Join-Path $Source 'res/msi')
try {
  $pre = @('preprocess.py', '-d', $dist, '-c', '--app-name', $appName, '-m', $manufacturer)
  if ($connType -and $connType -ne 'bidirectional') { $pre += @('--conn-type', $connType) }
  Invoke-Native { python @pre }
  Invoke-Native { nuget restore msi.sln }
  $platform = if ($Target -eq 'windows-aarch64') { 'ARM64' } else { 'x64' }
  Invoke-Native { msbuild msi.sln -p:Configuration=Release -p:Platform=$platform /p:TargetVersion=Windows10 }
  $msi = Get-ChildItem ./Package/bin/*/Release/en-us/Package.msi | Select-Object -First 1
  if (-not $msi) { throw 'Package.msi not produced' }
  Move-Item $msi.FullName (Join-Path $Out "$fileName-$Target.msi")
} finally { Pop-Location }

Get-ChildItem $Out

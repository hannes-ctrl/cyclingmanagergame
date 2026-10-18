# Builds the 3D viewer for Windows, Linux and macOS into viewer/build.
# Needs Godot 4.7 with its export templates; the path comes from GODOT or
# defaults to the portable install under D:\dev\godot.
param([string[]]$Platforms = @('Windows Desktop', 'Linux', 'macOS'))
$ErrorActionPreference = 'Stop'
$godot = if ($env:GODOT) { $env:GODOT } else { 'D:\dev\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' }
Set-Location $PSScriptRoot
$out = @{ 'Windows Desktop' = 'build/windows/RadmanagerViewer.exe'; 'Linux' = 'build/linux/RadmanagerViewer.x86_64'; 'macOS' = 'build/macos/RadmanagerViewer.zip' }
& $godot --headless --path . --import | Out-Null
foreach ($p in $Platforms) {
  New-Item -ItemType Directory -Force (Split-Path $out[$p]) | Out-Null
  & $godot --headless --path . --export-release $p $out[$p]
  if (-not (Test-Path $out[$p])) { throw "Export for $p failed" }
  Write-Host "Built $($out[$p])"
}

# Tunes the race simulation against real results.
#
#   .\kalibrieren.ps1            search for 8 hours (e.g. overnight)
#   .\kalibrieren.ps1 -Stunden 1
#   .\kalibrieren.ps1 -Bericht   only print the comparison real vs. simulation
#
# The run can be interrupted with Ctrl+C at any time: every improvement is
# written to data\calibration\tuning.json at once, and the next run
# continues from there. The log is in data\calibration\log.txt.
#
# -Stunden  hours to search
# -Laeufe   simulation runs per race (three are enough with several
#           hundred races; more makes every attempt slower)
# -Bericht  report only
param(
    [double]$Stunden = 8,
    [int]$Laeufe = 3,
    [switch]$Bericht
)

# Uses dart from the PATH. A file env.local.ps1 next to this script (not
# tracked) may set $env:RADMANAGER_DART and $env:PUB_CACHE for this machine.
if (Test-Path "$PSScriptRoot\env.local.ps1") { . "$PSScriptRoot\env.local.ps1" }
$dart = if ($env:RADMANAGER_DART) { $env:RADMANAGER_DART } else { 'dart' }
if (-not (Get-Command $dart -ErrorAction SilentlyContinue)) {
    Write-Error "dart was not found. Put it on the PATH or set RADMANAGER_DART in env.local.ps1."
    exit 1
}
Set-Location "$PSScriptRoot\packages\calibration"

# Fetch new results of all seasons; pages loaded before come from the cache.
foreach ($year in 2021..2026) {
    & $dart run bin/fetch_results.dart $year | Select-Object -Last 1
}

$out = "$PSScriptRoot\data\calibration"
if ($Bericht) {
    & $dart run bin/calibrate.dart report
} else {
    # Report before and after, so that the effect of the run can be compared.
    & $dart run bin/calibrate.dart report | Out-File -Encoding utf8 "$out\bericht_vorher.txt"
    & $dart run bin/calibrate.dart run --hours $Stunden --runs $Laeufe
    & $dart run bin/calibrate.dart report | Tee-Object -FilePath "$out\bericht.txt"
}

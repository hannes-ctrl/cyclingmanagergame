# Tunes the race simulation against real results.
#
#   .\calibrate.ps1                 search for 8 hours (e.g. overnight)
#   .\calibrate.ps1 -Hours 1
#   .\calibrate.ps1 -From 2021      include the earlier seasons
#   .\calibrate.ps1 -Report         only print the comparison real vs. simulation
#
# The run can be interrupted with Ctrl+C at any time: every improvement is
# written to data\calibration\tuning.json at once, and the next run
# continues from there. The log is in data\calibration\log.txt, the reports
# before and after a run in report_before.txt and report.txt.
#
# -Hours   hours to search
# -Runs    simulation runs per race (three are enough with several hundred
#          races; more makes every attempt slower)
# -From    first season to compare with; before 2023 the finishers the
#          database does not know are filled with anonymous riders
# -Report  report only
param(
    [double]$Hours = 8,
    [int]$Runs = 3,
    [int]$From = 2023,
    [switch]$Report
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
foreach ($year in $From..2026) {
    & $dart run bin/fetch_results.dart $year | Select-Object -Last 1
}

$out = "$PSScriptRoot\data\calibration"
if ($Report) {
    & $dart run bin/calibrate.dart report --from $From
} else {
    # Report before and after, so that the effect of the run can be compared.
    & $dart run bin/calibrate.dart report --from $From | Out-File -Encoding utf8 "$out\report_before.txt"
    & $dart run bin/calibrate.dart run --hours $Hours --runs $Runs --from $From
    & $dart run bin/calibrate.dart report --from $From | Tee-Object -FilePath "$out\report.txt"
}

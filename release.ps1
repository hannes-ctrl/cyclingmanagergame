# Builds the Windows release and packs it as a zip that runs on a clean
# Windows without the toolchain.
#
#   .\release.ps1                 program and tuning values only
#   .\release.ps1 -World          with the world database data\world.sqlite
#   .\release.ps1 -World -Art     also with jerseys, race logos and rider photos
#
# The world database and the pictures come from the WorldDB for Pro Cycling
# Manager and from the game itself: they are not ours to publish. Pass them
# on to friends privately at most; without them the program says where the
# database belongs.

param(
    [switch]$World,
    [switch]$Art
)

# Uses flutter from the PATH. A file env.local.ps1 next to this script (not
# tracked) may set $env:RADMANAGER_DART; flutter is taken from the same
# folder then.
if (Test-Path "$PSScriptRoot\env.local.ps1") { . "$PSScriptRoot\env.local.ps1" }
$flutter = if ($env:RADMANAGER_DART) {
    Join-Path (Split-Path $env:RADMANAGER_DART) 'flutter.bat'
} else { 'flutter' }

$version = (Select-String -Path "$PSScriptRoot\app\pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$name = "Radmanager-$($version -replace '\+.*$', '')"
$dist = "$PSScriptRoot\dist"
$out = "$dist\$name"
$data = "$PSScriptRoot\data"

Push-Location "$PSScriptRoot\app"
& $flutter build windows --release
$built = $LASTEXITCODE
Pop-Location
if ($built -ne 0) { Write-Error 'The build failed.'; exit 1 }

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
# The build comes first: its folder data holds the program itself, and the
# game keeps its own files beside it.
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item -Recurse "$PSScriptRoot\app\build\windows\x64\runner\Release\*" $out
New-Item -ItemType Directory -Force "$out\data\calibration" | Out-Null
Copy-Item "$data\calibration\tuning.json" "$out\data\calibration\"

# The Visual C++ runtime a Flutter program needs; a fresh Windows often
# lacks it. Microsoft allows these files to be passed on with a program.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    $from = "$env:SystemRoot\System32\$dll"
    if (Test-Path $from) { Copy-Item $from $out } else { Write-Warning "$dll not found" }
}

if ($World) {
    if (-not (Test-Path "$data\world.sqlite")) { Write-Error 'data\world.sqlite is missing.'; exit 1 }
    Copy-Item "$data\world.sqlite" "$out\data\"
}
if ($Art) {
    foreach ($dir in 'jerseys', 'logos', 'photos') {
        if (Test-Path "$data\$dir") { Copy-Item -Recurse "$data\$dir" "$out\data\$dir" }
    }
}

$database = if ($World) {
    'The world database is included.'
} else {
    @"
Copy the world database world.sqlite into the folder data next to
   radmanager.exe. It is built from the WorldDB for Pro Cycling Manager 2026
   with "worlddb import" (see the README of the project); it is not part of
   this download.
"@
}
@"
Radmanager $version

1. Unpack this folder anywhere, e.g. to Documents\Radmanager.
2. $database
3. Start radmanager.exe. Saves, settings and exports are kept in the folder
   data.

Windows 10 or 11, 64 bit. Nothing has to be installed.
"@ | Out-File -Encoding utf8 "$out\README.txt"

$zip = "$dist\$name-windows.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $out -DestinationPath $zip
Write-Output "Written: $zip"

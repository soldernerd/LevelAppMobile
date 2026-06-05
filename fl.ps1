# fl.ps1 — Flutter wrapper that pre-clears OneDrive-locked ephemeral dirs
# Usage: .\fl.ps1 run -d SM
#        .\fl.ps1 build apk
#        .\fl.ps1 clean

$base = $PSScriptRoot
$clearDirs = @(
    "$base\.dart_tool",
    "$base\build",
    "$base\ios\Flutter\ephemeral",
    "$base\macos\Flutter\ephemeral",
    "$base\linux\flutter\ephemeral",
    "$base\windows\flutter\ephemeral"
)

Write-Host "Clearing OneDrive-locked build dirs..." -ForegroundColor Cyan
foreach ($d in $clearDirs) {
    if (Test-Path $d) {
        & cmd /c "rd /s /q `"$d`"" 2>$null
    }
}

Write-Host "Running: flutter $args`n" -ForegroundColor Cyan
flutter @args

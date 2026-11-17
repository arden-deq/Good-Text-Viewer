param([string]$BuildDir = ".build/qt-windows-native")
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Invoke-Checked([scriptblock]$Step) {
    & $Step
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Step" }
}

Invoke-Checked { cmake -S . -B $BuildDir -G Ninja -DCMAKE_BUILD_TYPE=Release }
Invoke-Checked { cmake --build $BuildDir --parallel }
Invoke-Checked { ctest --test-dir $BuildDir --output-on-failure }

$Stage = Join-Path (Get-Location) ("dist/qt/windows-" + [guid]::NewGuid().ToString("N"))
try {
    Invoke-Checked { cmake --install $BuildDir --prefix $Stage }
    $Exe = Get-Item -LiteralPath (Join-Path $Stage "GoodTextViewer.exe")
    Invoke-Checked { windeployqt --release --no-translations $Exe.FullName }
    $Version = $Exe.VersionInfo.ProductVersion
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Missing product version on installed executable" }
    $Archive = Join-Path (Get-Location) "dist/Good-Text-Viewer-$Version-Windows-x64.zip"
    Compress-Archive -Path "$Stage/*" -DestinationPath $Archive -Force
    $Hash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
    "$Hash  $(Split-Path -Leaf $Archive)" | Set-Content -LiteralPath "$Archive.sha256" -Encoding ascii
    Write-Output "Created: $Archive"
} finally {
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
}

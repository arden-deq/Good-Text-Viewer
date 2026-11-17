param([string]$BuildDir = ".build/qt-windows-native", [switch]$PortableExe)
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

    if ($PortableExe) {
        $Compiler = Join-Path ${env:ProgramFiles(x86)} "NSIS/makensis.exe"
        if (-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) {
            $Compiler = (Get-Command makensis.exe -ErrorAction Stop).Source
        }
        $Portable = Join-Path (Get-Location) "dist/Good-Text-Viewer-$Version-Windows-x64.exe"
        $Icon = Join-Path (Get-Location) "Assets/AppIcon.ico"
        Invoke-Checked {
            & $Compiler "/DSOURCE_DIR=$Stage" "/DOUTPUT_EXE=$Portable" "/DAPP_ICON=$Icon" "Packaging/windows/Portable.nsi"
        }
        $Hash = (Get-FileHash -LiteralPath $Portable -Algorithm SHA256).Hash.ToLowerInvariant()
        "$Hash  $(Split-Path -Leaf $Portable)" | Set-Content -LiteralPath "$Portable.sha256" -Encoding ascii
        Write-Output "Created: $Portable"
    }
} finally {
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
}

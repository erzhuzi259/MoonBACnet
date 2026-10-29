$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outputPath = Join-Path $repoPath '_build\windows-path-shims'
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$visualStudioPath = & $vswherePath -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $visualStudioPath) { throw 'MSVC is required to build the Windows argv adapter' }
$devCommand = Join-Path $visualStudioPath 'Common7\Tools\VsDevCmd.bat'
$sourcePath = Join-Path $PSScriptRoot 'path_shim.c'
$buildFile = Join-Path $outputPath 'build.cmd'
@"
@echo off
call "$devCommand" -no_logo -arch=x64
if errorlevel 1 exit /b 1
cl /nologo /O2 /W4 /D_CRT_SECURE_NO_WARNINGS "$sourcePath" /Fe:"$outputPath\moonc.exe" /Fo:"$outputPath\path_shim.obj"
"@ | Set-Content -LiteralPath $buildFile -Encoding ascii
& cmd.exe /d /c $buildFile
if ($LASTEXITCODE -ne 0) { throw 'Windows argv adapter build failed' }
foreach ($toolName in @('moonfmt.exe', 'mooninfo.exe', 'moondoc.exe')) {
    Copy-Item -LiteralPath (Join-Path $outputPath 'moonc.exe') -Destination (Join-Path $outputPath $toolName) -Force
}
Write-Output $outputPath

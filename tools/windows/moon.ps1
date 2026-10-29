# Use the installed official moon/moonc; normalize Windows extended paths only
# for compiler/formatter child processes. No global environment is modified.
$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$shimPath = Join-Path $repoPath '_build\windows-path-shims'
if (-not (Test-Path -LiteralPath (Join-Path $shimPath 'moonc.exe'))) {
    & (Join-Path $PSScriptRoot 'build-shim.ps1') | Out-Host
}
$previousValues = @{}
foreach ($entry in @(@('MOONC_OVERRIDE','moonc.exe'), @('MOONFMT_OVERRIDE','moonfmt.exe'), @('MOONINFO_OVERRIDE','mooninfo.exe'), @('MOONDOC_OVERRIDE','moondoc.exe'))) {
    $previousValues[$entry[0]] = [Environment]::GetEnvironmentVariable($entry[0], 'Process')
    [Environment]::SetEnvironmentVariable($entry[0], (Join-Path $shimPath $entry[1]), 'Process')
}
try {
    & moon.exe @args
    $moonExitCode = $LASTEXITCODE
} finally {
    foreach ($entry in $previousValues.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}
exit $moonExitCode

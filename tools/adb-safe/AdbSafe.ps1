#Requires -Version 5.1
# Tuong thich — chuyen sang Fix-Xanh-Man\Fix.ps1
$fix = Join-Path $PSScriptRoot '..\..\Fix-Xanh-Man\Fix.ps1'
if (-not (Test-Path -LiteralPath $fix)) {
    Write-Host "Thieu Fix.ps1: $fix" -ForegroundColor Red
    exit 1
}
& $fix @args
exit $LASTEXITCODE

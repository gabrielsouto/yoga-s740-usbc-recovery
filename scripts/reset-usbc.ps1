param(
    [switch]$AllowUnvalidatedModel
)

$ErrorActionPreference = 'Stop'
$installedScript = Join-Path $env:ProgramData 'UsbCRecovery\UsbCRecovery.ps1'
$localScript = Join-Path $PSScriptRoot 'UsbCRecovery.ps1'

if (Test-Path -LiteralPath $installedScript) {
    $target = $installedScript
}
elseif (Test-Path -LiteralPath $localScript) {
    $target = $localScript
}
else {
    throw 'UsbCRecovery.ps1 não foi encontrado. Execute install.ps1 ou use o repositório completo.'
}

$arguments = @{
    ForceReset = $true
}

if ($AllowUnvalidatedModel) {
    $arguments.AllowUnvalidatedModel = $true
}

& $target @arguments
exit $LASTEXITCODE

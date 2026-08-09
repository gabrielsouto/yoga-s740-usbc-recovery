param()

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Abra o PowerShell como administrador e execute uninstall.ps1 novamente.'
}

$installDir = Join-Path $env:ProgramData 'UsbCRecovery'
$expectedDir = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'UsbCRecovery'))
$taskName = 'USB-C Recovery - Yoga S740'
$configPath = Join-Path $installDir 'UsbCRecovery.config.json'
$registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Tarefa removida: $taskName"
}

if (Test-Path -LiteralPath $configPath) {
    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.PreviousTestInterfaceValuePresent -eq $true) {
            New-Item -Path $registryPath -Force | Out-Null
            New-ItemProperty -Path $registryPath -Name TestInterfaceEnabled -PropertyType DWord -Value ([int]$config.PreviousTestInterfaceValue) -Force | Out-Null
            Write-Host 'Valor anterior de TestInterfaceEnabled restaurado.'
        }
        elseif ($config.PreviousTestInterfaceValuePresent -eq $false) {
            Remove-ItemProperty -Path $registryPath -Name TestInterfaceEnabled -ErrorAction SilentlyContinue
            Write-Host 'TestInterfaceEnabled removido, pois não existia antes da instalação.'
        }
    }
    catch {
        Write-Warning "Não foi possível restaurar TestInterfaceEnabled: $($_.Exception.Message)"
    }
}

if ([IO.Path]::GetFullPath($installDir) -ne $expectedDir) {
    throw 'Caminho de instalação inesperado; nenhum arquivo foi removido.'
}

if (Test-Path -LiteralPath $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
    Write-Host "Arquivos removidos: $installDir"
}
else {
    Write-Host 'A instalação não estava presente.'
}

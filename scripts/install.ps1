param(
    [switch]$EnableTestInterface,
    [switch]$SkipModelValidation,
    [string]$UcsiControlPath = 'C:\Program Files (x86)\USBTest\x64\UcsiControl.exe'
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra o PowerShell como administrador e execute install.ps1 novamente.'
    }
}

function Copy-PowerShellScriptAsUtf8Bom {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    # Windows PowerShell 5.1 interpreta arquivos UTF-8 sem BOM usando a página de
    # código ANSI do sistema. Como os scripts contêm mensagens em português, isso
    # pode gerar texto como "inÃ­cio" no log. Grave explicitamente os scripts
    # instalados como UTF-8 com BOM para que PowerShell.exe 5.1 os leia corretamente.
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $text = [IO.File]::ReadAllText($Source, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($Destination, $text, $utf8Bom)
}

Assert-Administrator

$installDir = Join-Path $env:ProgramData 'UsbCRecovery'
$taskName = 'USB-C Recovery - Yoga S740'
$configPath = Join-Path $installDir 'UsbCRecovery.config.json'
$registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'

New-Item -ItemType Directory -Path $installDir -Force | Out-Null

foreach ($scriptName in @('UsbCRecovery.ps1', 'diagnose.ps1', 'reset-usbc.ps1')) {
    Copy-PowerShellScriptAsUtf8Bom `
        -Source (Join-Path $PSScriptRoot $scriptName) `
        -Destination (Join-Path $installDir $scriptName)
}

# Em uma reinstalação, preserve o estado ORIGINAL salvo pela primeira instalação.
# Caso contrário, TestInterfaceEnabled=1 (definido pelo próprio projeto) passaria
# a ser registrado como o valor anterior e a desinstalação não conseguiria mais
# restaurar corretamente a situação pré-instalação.
$previousValuePresent = $false
$previousValue = $null
$previousStateLoadedFromConfig = $false

if (Test-Path -LiteralPath $configPath) {
    try {
        $existingConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $existingConfig.PreviousTestInterfaceValuePresent) {
            $previousValuePresent = [bool]$existingConfig.PreviousTestInterfaceValuePresent
            if ($previousValuePresent -and $null -ne $existingConfig.PreviousTestInterfaceValue) {
                $previousValue = [int]$existingConfig.PreviousTestInterfaceValue
            }
            $previousStateLoadedFromConfig = $true
            Write-Host 'Estado original de TestInterfaceEnabled preservado da instalação existente.'
        }
    }
    catch {
        Write-Warning "Não foi possível ler o estado anterior da configuração existente: $($_.Exception.Message)"
    }
}

if (-not $previousStateLoadedFromConfig -and (Test-Path -LiteralPath $registryPath)) {
    try {
        $old = Get-ItemProperty -Path $registryPath -Name TestInterfaceEnabled -ErrorAction Stop
        $previousValuePresent = $true
        $previousValue = [int]$old.TestInterfaceEnabled
    }
    catch {
        $previousValuePresent = $false
    }
}

if ($EnableTestInterface) {
    New-Item -Path $registryPath -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name TestInterfaceEnabled -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Host "TestInterfaceEnabled=1 definido em $registryPath"
}
else {
    Write-Warning 'TestInterfaceEnabled não foi alterado. Use -EnableTestInterface se UcsiControl exigir a interface de teste.'
}

# A Lenovo identifica o Yoga S740-14IIL pelos Machine Types 81RM (Brasil) e
# 81RS. Em algumas instalações do Windows, Win32_ComputerSystem.Model retorna
# somente o Machine Type em vez do nome comercial do notebook.
$modelPatterns = @(
    '81RM'
    '81RS'
    '*Yoga S740-14IIL*'
)
if ($SkipModelValidation) {
    $modelPatterns = @('*')
}

$config = [ordered]@{
    ModelPatterns = $modelPatterns
    UcsiControlPath = $UcsiControlPath
    Signatures = @(
        'DISPLAY\SAM730B*'
        'DISPLAY\SAM730E*'
        'USB\VID_05E3&PID_0626*'
        'USB\VID_0B95&PID_1790*'
    )
    InitialDelaySeconds = 30
    RetryDelaySeconds = 10
    RecoveryDelaySeconds = 8
    MaxAutomaticResetsPerBoot = 1
    PreviousTestInterfaceValuePresent = $previousValuePresent
    PreviousTestInterfaceValue = $previousValue
}
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath -Encoding UTF8

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$mainScript = Join-Path $installDir 'UsbCRecovery.ps1'
$actionArguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $mainScript
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $actionArguments
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Detecta uma falha conhecida de USB-C no Yoga S740 e tenta UCSI CONNECTOR_RESET uma vez por boot.' -Force | Out-Null

Write-Host
Write-Host 'Instalação concluída.'
Write-Host "Arquivos: $installDir"
Write-Host "Tarefa: $taskName"
Write-Host 'Modelos validados por padrão: Yoga S740-14IIL Machine Types 81RM e 81RS.'
Write-Host 'O script aguarda 30 segundos no boot, verifica duas vezes e faz no máximo um reset automático.'
Write-Host 'Teste manual:'
Write-Host "  & '$installDir\reset-usbc.ps1'"
Write-Host 'Diagnóstico:'
Write-Host "  & '$installDir\diagnose.ps1'"

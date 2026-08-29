param(
    [switch]$ForceReset,
    [switch]$NoInitialDelay,
    [switch]$AllowUnvalidatedModel
)

$ErrorActionPreference = 'Stop'

$BaseDir = Join-Path $env:ProgramData 'UsbCRecovery'
$LogFile = Join-Path $BaseDir 'UsbCRecovery.log'
$ConfigFile = Join-Path $BaseDir 'UsbCRecovery.config.json'
$DefaultUcsiControl = 'C:\Program Files (x86)\USBTest\x64\UcsiControl.exe'
$UCSIInstanceId = 'ACPI\USBC000\0'
$UCSIParametersPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'
$DefaultModelPatterns = @(
    '81RM'
    '81RS'
    '*Yoga S740-14IIL*'
)

function Ensure-BaseDirectory {
    if (-not (Test-Path -LiteralPath $BaseDir)) {
        New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    }
}

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)

    Ensure-BaseDirectory
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp  $Message"
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8

    if ([Environment]::UserInteractive) {
        Write-Host $line
    }
}

function Get-RecoveryConfig {
    $defaults = [pscustomobject]@{
        ModelPatterns = $DefaultModelPatterns
        UcsiControlPath = $DefaultUcsiControl
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
    }

    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        return $defaults
    }

    try {
        $loaded = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $defaults.PSObject.Properties.Name) {
            if ($null -eq $loaded.$property) {
                $loaded | Add-Member -NotePropertyName $property -NotePropertyValue $defaults.$property
            }
        }

        # Compatibilidade com instalações anteriores a 2026-08-29. A versão
        # antiga usava apenas o nome comercial, mas o Yoga S740-14IIL pode ser
        # reportado por Win32_ComputerSystem.Model somente como 81RM ou 81RS.
        $configuredPatterns = @($loaded.ModelPatterns)
        if ($configuredPatterns.Count -eq 1 -and [string]$configuredPatterns[0] -eq '*Yoga S740-14IIL*') {
            $loaded.ModelPatterns = $DefaultModelPatterns
            Write-Log 'Configuração de modelo antiga detectada; adicionando Machine Types 81RM e 81RS em memória.'
        }

        return $loaded
    }
    catch {
        Write-Log "AVISO: configuração inválida; usando padrões. $($_.Exception.Message)"
        return $defaults
    }
}

function Get-SystemIdentity {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS

    [pscustomobject]@{
        Manufacturer = $computer.Manufacturer
        Model = $computer.Model
        BIOSVersion = ($bios.SMBIOSBIOSVersion -join ', ')
        BIOSReleaseDate = $bios.ReleaseDate
    }
}

function Test-ModelAllowed {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [switch]$PermitUnvalidated
    )

    $identity = Get-SystemIdentity
    Write-Log "Sistema: $($identity.Manufacturer) $($identity.Model) | BIOS: $($identity.BIOSVersion)"

    if ($PermitUnvalidated) {
        Write-Log 'AVISO: modelo não validado foi permitido explicitamente para esta execução.'
        return $true
    }

    foreach ($pattern in @($Config.ModelPatterns)) {
        if ($identity.Model -like [string]$pattern) {
            Write-Log "Modelo validado: $($identity.Model) | padrão=$pattern"
            return $true
        }
    }

    Write-Log "ERRO: modelo não validado: $($identity.Model). Nenhum reset foi enviado."
    Write-Log 'Use -AllowUnvalidatedModel somente se você estiver fazendo um teste consciente em outro equipamento.'
    return $false
}

function Test-UcsiReady {
    param([Parameter(Mandatory = $true)]$Config)

    $device = Get-PnpDevice -InstanceId $UCSIInstanceId -ErrorAction SilentlyContinue
    if (-not $device) {
        Write-Log "ERRO: dispositivo UCSI não encontrado: $UCSIInstanceId"
        return $false
    }

    Write-Log "UCSI: $($device.Status) | $($device.FriendlyName) | $($device.InstanceId)"
    if ($device.Status -ne 'OK') {
        Write-Log "ERRO: UCSI encontrado, mas status = $($device.Status)."
        return $false
    }

    $ucsiPath = [string]$Config.UcsiControlPath
    if (-not (Test-Path -LiteralPath $ucsiPath)) {
        Write-Log "ERRO: UcsiControl.exe não encontrado: $ucsiPath"
        Write-Log 'Obtenha-o de uma instalação legítima do pacote Microsoft USB Test Tool (MUTT).'
        return $false
    }

    try {
        $testInterface = Get-ItemProperty -Path $UCSIParametersPath -Name TestInterfaceEnabled -ErrorAction Stop
        if ([int]$testInterface.TestInterfaceEnabled -ne 1) {
            Write-Log 'ERRO: TestInterfaceEnabled não está definido como 1.'
            Write-Log "Ative-o somente conforme a documentação: $UCSIParametersPath"
            return $false
        }
    }
    catch {
        Write-Log "ERRO: não foi possível verificar TestInterfaceEnabled em $UCSIParametersPath"
        return $false
    }

    return $true
}

function Get-UsbCEvidence {
    param([Parameter(Mandatory = $true)]$Config)

    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)
    $matches = @()

    foreach ($device in $devices) {
        foreach ($signature in @($Config.Signatures)) {
            if ($device.InstanceId -like [string]$signature) {
                $matches += [pscustomobject]@{
                    Class = $device.Class
                    Status = $device.Status
                    FriendlyName = $device.FriendlyName
                    InstanceId = $device.InstanceId
                    Signature = [string]$signature
                }
                break
            }
        }
    }

    return $matches
}

function Write-UsbCEvidence {
    param([Parameter(Mandatory = $true)]$Evidence)

    foreach ($device in @($Evidence)) {
        $message = 'Evidência: {0} | {1} | {2} | assinatura={3}' -f $device.Status, $device.Class, $device.FriendlyName, $device.Signature
        Write-Log $message
    }
}

function Invoke-ConnectorReset {
    param([Parameter(Mandatory = $true)]$Config)

    $ucsiPath = [string]$Config.UcsiControlPath
    Write-Log 'Enviando UCSI CONNECTOR_RESET soft: Send 0 10003'

    $output = @(& $ucsiPath Send 0 10003 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    $text = ($output -join '').Trim()

    if ($text) {
        foreach ($line in ($text -split '\r?\n')) {
            if ($line.Trim()) {
                Write-Log "UcsiControl: $($line.Trim())"
            }
        }
    }

    if ($exitCode -ne 0) {
        Write-Log "ERRO: UcsiControl.exe retornou código $exitCode."
        return $false
    }

    Write-Log 'CONNECTOR_RESET enviado com sucesso.'
    return $true
}

function Sleep-IfNeeded {
    param(
        [int]$Seconds,
        [string]$Reason
    )

    if ($Seconds -gt 0) {
        Write-Log "$Reason Aguardando $Seconds segundo(s)."
        Start-Sleep -Seconds $Seconds
    }
}

try {
    Ensure-BaseDirectory
    $config = Get-RecoveryConfig
    Write-Log '--- início da verificação USB-C ---'

    if (-not (Test-ModelAllowed -Config $config -PermitUnvalidated:$AllowUnvalidatedModel)) {
        exit 2
    }

    if (-not (Test-UcsiReady -Config $config)) {
        exit 2
    }

    if ($ForceReset) {
        Write-Log 'Modo manual/forçado: a detecção de evidência foi ignorada.'
        if (-not (Invoke-ConnectorReset -Config $config)) {
            exit 1
        }

        Sleep-IfNeeded -Seconds ([int]$config.RecoveryDelaySeconds) -Reason 'Após o reset.'
        $evidence = @(Get-UsbCEvidence -Config $config)
        if ($evidence.Count -gt 0) {
            Write-UsbCEvidence -Evidence $evidence
            Write-Log 'USB-C recuperada ou evidência conhecida detectada após o reset.'
            exit 0
        }

        Write-Log 'AVISO: reset concluído, mas nenhuma evidência configurada apareceu depois.'
        exit 1
    }

    if (-not $NoInitialDelay) {
        Sleep-IfNeeded -Seconds ([int]$config.InitialDelaySeconds) -Reason 'Aguardando a enumeração normal do Windows.'
    }

    $evidence = @(Get-UsbCEvidence -Config $config)
    if ($evidence.Count -gt 0) {
        Write-UsbCEvidence -Evidence $evidence
        Write-Log 'USB-C parece saudável; nenhum reset foi necessário.'
        exit 0
    }

    Write-Log 'Nenhuma evidência conhecida encontrada na primeira verificação.'
    Sleep-IfNeeded -Seconds ([int]$config.RetryDelaySeconds) -Reason 'Antes da segunda verificação.'

    $evidence = @(Get-UsbCEvidence -Config $config)
    if ($evidence.Count -gt 0) {
        Write-UsbCEvidence -Evidence $evidence
        Write-Log 'Evidência apareceu na segunda verificação; nenhum reset foi necessário.'
        exit 0
    }

    if ([int]$config.MaxAutomaticResetsPerBoot -lt 1) {
        Write-Log 'Configuração impede reset automático; encerrando.'
        exit 1
    }

    Write-Log 'Duas verificações falharam; executando uma única recuperação automática.'
    if (-not (Invoke-ConnectorReset -Config $config)) {
        exit 1
    }

    Sleep-IfNeeded -Seconds ([int]$config.RecoveryDelaySeconds) -Reason 'Após a recuperação.'
    $evidence = @(Get-UsbCEvidence -Config $config)
    if ($evidence.Count -gt 0) {
        Write-UsbCEvidence -Evidence $evidence
        Write-Log 'Recuperação concluída: evidência conhecida detectada.'
        exit 0
    }

    Write-Log 'AVISO: o reset foi enviado, mas a evidência configurada continuou ausente.'
    exit 1
}
catch {
    try {
        Write-Log "ERRO inesperado: $($_.Exception.Message)"
    }
    catch {
        Write-Error $_
    }
    exit 1
}

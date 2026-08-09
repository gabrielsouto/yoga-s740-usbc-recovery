param(
    [string]$OutputPath,
    [switch]$SkipReadOnlyUCSICommands
)

$ErrorActionPreference = 'Continue'
$BaseDir = Join-Path $env:ProgramData 'UsbCRecovery'
$ConfigFile = Join-Path $BaseDir 'UsbCRecovery.config.json'
$DefaultUcsiControl = 'C:\Program Files (x86)\USBTest\x64\UcsiControl.exe'
$UCSIInstanceId = 'ACPI\USBC000\0'
$UCSIParametersPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path (Get-Location) "UsbCRecovery-diagnostic-$stamp.txt"
}

if (Test-Path -LiteralPath $ConfigFile) {
    try {
        $config = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $config = $null
    }
}

if (-not $config) {
    $config = [pscustomobject]@{
        UcsiControlPath = $DefaultUcsiControl
        Signatures = @(
            'DISPLAY\SAM730B*'
            'DISPLAY\SAM730E*'
            'USB\VID_05E3&PID_0626*'
            'USB\VID_0B95&PID_1790*'
        )
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
function Add-Line {
    param([AllowEmptyString()][string]$Value = '')
    [void]$lines.Add($Value)
}
function Add-Section {
    param([string]$Title)
    Add-Line
    Add-Line ('=' * 78)
    Add-Line $Title
    Add-Line ('=' * 78)
}
function Add-CommandOutput {
    param(
        [string]$Label,
        [scriptblock]$Command
    )

    Add-Line
    Add-Line "[$Label]"
    try {
        $result = (& $Command 2>&1 | Out-String -Width 240).TrimEnd()
        if ($result) {
            foreach ($line in ($result -split '\r?\n')) {
                Add-Line $line
            }
        }
        else {
            Add-Line '<sem saída>'
        }
    }
    catch {
        Add-Line "ERRO: $($_.Exception.Message)"
    }
}

Add-Section 'USB-C Recovery diagnostic report'
Add-Line "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
Add-Line 'This report intentionally excludes user files and does not collect serial numbers.'

Add-Section 'System identity'
Add-CommandOutput 'Win32_ComputerSystem' {
    Get-CimInstance Win32_ComputerSystem |
        Select-Object Manufacturer, Model, SystemType |
        Format-List
}
Add-CommandOutput 'Win32_BIOS' {
    Get-CimInstance Win32_BIOS |
        Select-Object SMBIOSBIOSVersion, ReleaseDate, Manufacturer |
        Format-List
}
Add-CommandOutput 'Windows version' {
    Get-ComputerInfo |
        Select-Object WindowsProductName, WindowsVersion, OsBuildNumber |
        Format-List
}

Add-Section 'UCSI and test interface'
Add-CommandOutput 'UCSI PnP device' {
    Get-PnpDevice -InstanceId $UCSIInstanceId -ErrorAction SilentlyContinue |
        Select-Object Status, Class, FriendlyName, InstanceId |
        Format-List
}
Add-CommandOutput 'UCSI-related drivers' {
    Get-CimInstance Win32_SystemDriver |
        Where-Object Name -match 'Ucsi|Ucm' |
        Select-Object Name, State, StartMode, PathName |
        Format-Table -AutoSize
}
Add-CommandOutput 'TestInterfaceEnabled' {
    Get-ItemProperty -Path $UCSIParametersPath -Name TestInterfaceEnabled -ErrorAction SilentlyContinue |
        Select-Object PSPath, TestInterfaceEnabled |
        Format-List
}
Add-CommandOutput 'Configured UcsiControl path' {
    [pscustomobject]@{
        Path = [string]$config.UcsiControlPath
        Exists = Test-Path -LiteralPath ([string]$config.UcsiControlPath)
    } | Format-List
}

Add-Section 'Configured detection signatures'
foreach ($signature in @($config.Signatures)) {
    Add-Line ([string]$signature)
}

Add-Section 'Present evidence devices'
Add-CommandOutput 'PnP evidence' {
    $devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)
    $devices | Where-Object {
        $current = $_
        @($config.Signatures) | Where-Object {
            $current.InstanceId -like [string]$_
        }
    } | Select-Object Status, Class, FriendlyName, InstanceId |
        Format-Table -AutoSize
}

if (-not $SkipReadOnlyUCSICommands -and (Test-Path -LiteralPath ([string]$config.UcsiControlPath))) {
    Add-Section 'Read-only UCSI commands'
    Add-CommandOutput 'GET_CAPABILITY (Send 0 6)' {
        & ([string]$config.UcsiControlPath) Send 0 6
    }
    Add-CommandOutput 'GET_CONNECTOR_STATUS for connector 1 (Send 0 010012)' {
        & ([string]$config.UcsiControlPath) Send 0 010012
    }
    Add-CommandOutput 'GET_ERROR_STATUS (Send 0 13)' {
        & ([string]$config.UcsiControlPath) Send 0 13
    }
}

Add-Section 'Interpretation'
Add-Line 'This report is evidence for troubleshooting, not a diagnosis by itself.'
Add-Line 'The recovery project was validated on one Lenovo Yoga S740-14IIL.'
Add-Line 'Do not attach reports containing unrelated personal information.'

$lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Relatório salvo em: $OutputPath"

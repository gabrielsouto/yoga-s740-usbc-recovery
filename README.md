# Yoga S740 USB-C Recovery

**English** | [Português (Brasil)](README.pt-BR.md)

A diagnostic and recovery tool for an intermittent USB-C/Thunderbolt failure state observed on the Lenovo Yoga S740-14IIL.

> [!WARNING]
> This project is experimental. It is not an official Lenovo or Microsoft driver, and it does not claim to fix every USB-C failure. Anyone who chooses to use it does so entirely at their own risk. There is no guarantee of recovery, compatibility, or freedom from side effects. Back up your data, keep an alternative way to access the computer, and read the limitations before sending any reset command.

## One-sentence summary

On the investigated laptop, Windows continued to report UCSI, xHCI, and Thunderbolt as healthy, but the USB-C connector did not enumerate a connected hub or monitor; sending a soft UCSI `CONNECTOR_RESET` with `UcsiControl.exe Send 0 10003` recovered the port without restarting the computer.

## What this repository provides

- a manual and auditable procedure for testing the hypothesis;
- a PowerShell diagnostic script that creates a report without collecting personal files;
- a manual recovery script;
- an optional Scheduled Task that checks the port at boot;
- configurable detection based on known device signatures;
- logs at `C:\ProgramData\UsbCRecovery\UsbCRecovery.log`;
- installation and removal instructions;
- documentation of the investigation, failed tests, and limitations.

The recommended path is always: diagnose first, test manually, observe the behavior over more than one usage cycle, and only then install the automatic recovery.

## Validated scope

| Item | Available evidence |
| --- | --- |
| Laptop | Lenovo Yoga S740-14IIL |
| Investigated operating system | Windows 11 x64 |
| UCSI | `ACPI\USBC000\0`, status `OK` |
| UCSI client | `UcmUcsiAcpiClient.sys` |
| Observed BIOS | `BYCN39WW` |
| Hub evidence | `USB\VID_05E3&PID_0626*` and `USB\VID_0B95&PID_1790*` |
| DisplayPort evidence | `DISPLAY\SAM730E*` |
| HDMI/hub evidence | `DISPLAY\SAM730B*` |
| Decisive command | `UcsiControl.exe Send 0 10003` |
| Manual result | immediate USB-C recovery without reboot |
| Automatic boot result | confirmed on 2026-08-09 during a natural failure at startup |
| Automatic command result | `CommandCompletedIndicator: 1`, `ErrorIndicator: 0`, exit code `0` |
| Post-reset evidence | SuperSpeed hub, Samsung HDMI display, and ASIX Ethernet adapter re-enumerated about 9 seconds later |

These data describe one validated case, not a compatibility matrix. Another Yoga S740 may have a different BIOS, topology, Windows version, or underlying failure.

## Compatible symptom

The investigated case usually appeared as follows:

1. the laptop started with a USB-C hub or USB-C-to-DisplayPort cable connected;
2. USB-C provided no data or video even though Windows finished starting;
3. the main devices and drivers still appeared as `OK`;
4. disconnecting and reconnecting the hub did not create new PnP devices;
5. restarting Thunderbolt, xHCI, the root hub, or the UCSI device did not recover the connection;
6. a complete physical power cycle could recover the port;
7. a soft `CONNECTOR_RESET` recovered the port without restarting Windows.

If your symptoms differ, especially if there is physical damage, overheating, charging failure, liquid exposure, a burning smell, or a persistent Device Manager error, do not treat this project as a solution.

## Safest manual test

### 1. Confirm the computer model

Open PowerShell as Administrator and run:

~~~powershell
Get-CimInstance Win32_ComputerSystem |
    Select-Object Manufacturer,Model

Get-CimInstance Win32_BIOS |
    Select-Object SMBIOSBIOSVersion,ReleaseDate

Get-PnpDevice -InstanceId 'ACPI\USBC000\0' |
    Format-Table Status,Class,FriendlyName,InstanceId -Auto
~~~

Do not use the automatic reset on another model without understanding and accepting the risk. The script blocks unvalidated models by default.

### 2. Confirm UCSI and the test interface

The script expects:

~~~text
ACPI\USBC000\0
Status: OK
TestInterfaceEnabled: 1
~~~

Check the value:

~~~powershell
$ucsiParameters = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'
Get-ItemProperty -Path $ucsiParameters -Name TestInterfaceEnabled
~~~

If the value does not exist, this is the procedure used during the investigation:

~~~powershell
$ucsiParameters = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'
New-Item -Path $ucsiParameters -Force | Out-Null
New-ItemProperty -Path $ucsiParameters -Name TestInterfaceEnabled -PropertyType DWord -Value 1 -Force
~~~

This changes the Windows Registry. Create a restore point or export the registry key first, understand how to undo the change, and proceed only if you accept the risk. This repository's installer records the previous value and attempts to restore it during uninstallation.

### 3. Obtain UcsiControl.exe legitimately

The executable is not distributed in this repository. It belongs to Microsoft's USB test tooling and may be available through a legitimate installation of the MUTT/USBTest package. Microsoft's official documentation describes the package, UCSI commands, and the typical installation path used in the investigated case:

- [USB-C Connector System Software Interface (UCSI) Driver](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/ucsi)
- [Tools in the MUTT Software Package](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/mutt-software-package)

Do not download executables from third-party websites, accept modified versions, or add a proprietary copy to this repository without redistribution rights.

The path expected by the script is:

~~~text
C:\Program Files (x86)\USBTest\x64\UcsiControl.exe
~~~

If your legitimate installation uses another path, pass it to the installer or edit `C:\ProgramData\UsbCRecovery\UsbCRecovery.config.json`.

### 4. Capture read-only information before resetting

With the hub or monitor connected and the failure present, capture:

~~~powershell
$ucsi = 'C:\Program Files (x86)\USBTest\x64\UcsiControl.exe'

& $ucsi Send 0 6
& $ucsi Send 0 010012
& $ucsi Send 0 13
~~~

These commands are used here to read capability, connector status, and error status. Save the output for comparison. In the investigated case, `GET_CONNECTOR_STATUS` reported `ConnectStatus=0` even though a device was physically connected.

### 5. Send the manual reset

Only after confirming the model, UCSI device, and executable path:

~~~powershell
& 'C:\Program Files (x86)\USBTest\x64\UcsiControl.exe' Send 0 10003
~~~

In the tool's syntax, `10003` is a soft `CONNECTOR_RESET` for connector 1. Do not start with the `810003` hard reset: the soft reset was sufficient in the validated case, while the hard reset is a more aggressive intervention.

Wait a few seconds, then check whether the hub or monitor appears:

~~~powershell
Get-PnpDevice -PresentOnly |
    Where-Object {
        $_.InstanceId -like 'DISPLAY\SAM730B*' -or
        $_.InstanceId -like 'DISPLAY\SAM730E*' -or
        $_.InstanceId -like 'USB\VID_05E3&PID_0626*' -or
        $_.InstanceId -like 'USB\VID_0B95&PID_1790*'
    } |
    Format-Table Status,Class,FriendlyName,InstanceId -Auto
~~~

## Installing automatic recovery

Use this only after the manual test succeeds and after accepting that the command will run as `SYSTEM` during startup.

~~~powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\install.ps1 -EnableTestInterface
~~~

The installer:

- copies the scripts to `C:\ProgramData\UsbCRecovery`;
- creates the configuration file;
- records the previous `TestInterfaceEnabled` value;
- optionally sets `TestInterfaceEnabled=1`;
- creates the `USB-C Recovery - Yoga S740` Scheduled Task;
- runs under the `SYSTEM` account with elevated privileges;
- waits 30 seconds;
- checks for known devices;
- waits another 10 seconds if no evidence is found;
- sends at most one automatic `CONNECTOR_RESET` per startup;
- waits 8 seconds and logs the result.

If the executable is installed elsewhere:

~~~powershell
.\scripts\install.ps1 -EnableTestInterface -UcsiControlPath 'D:\Tools\USBTest\x64\UcsiControl.exe'
~~~

### Confirmed automatic recovery during a real boot failure

On 2026-08-09, the installed Scheduled Task recovered the port automatically during a natural occurrence of the problem at startup. No reboot or manual intervention was used. The task found `ACPI\USBC000\0` in `OK` state, but the expected USB-C devices were absent at the first and second checks. It then sent:

~~~text
UcsiControl.exe Send 0 10003
~~~

The tool reported `Command completed successfully`, `ErrorIndicator: 0`, `CommandCompletedIndicator: 1`, and exit code `0`. About nine seconds later, Windows re-enumerated the expected `Generic SuperSpeed USB Hub`, Samsung monitor on HDMI, and ASIX USB-to-Gigabit Ethernet adapter. This confirms the automatic recovery path for this observed case; it is not a universal fix or a guarantee for other systems.

`ResetCompletedIndicator: 0` does not invalidate this result. For this command, the relevant completion evidence was `CommandCompletedIndicator: 1` together with the subsequent physical/PnP enumeration of the USB-C devices.

By default, the installer accepts only `*Yoga S740-14IIL*` as a model. Model validation can be disabled for a deliberate investigation on another computer, but doing so increases the risk:

~~~powershell
.\scripts\install.ps1 -EnableTestInterface -SkipModelValidation
~~~

Do not use this option merely to bypass an error without understanding its cause.

## Manual use after installation

If USB-C becomes stuck during normal use:

~~~powershell
& 'C:\ProgramData\UsbCRecovery\reset-usbc.ps1'
~~~

This command skips hub/monitor detection and sends the soft reset directly, but it still checks the computer model, UCSI device, executable, and `TestInterfaceEnabled`.

To generate a diagnostic report:

~~~powershell
& 'C:\ProgramData\UsbCRecovery\diagnose.ps1'
~~~

The report includes the model, BIOS, UCSI device, related drivers, configuration, signatures, and read-only UCSI commands. It does not collect user files and should not be published without review.

## Configurable detection

The file:

~~~text
C:\ProgramData\UsbCRecovery\UsbCRecovery.config.json
~~~

contains the signatures that represent a healthy USB-C connection in the validated case:

~~~json
{
  "Signatures": [
    "DISPLAY\\SAM730B*",
    "DISPLAY\\SAM730E*",
    "USB\\VID_05E3&PID_0626*",
    "USB\\VID_0B95&PID_1790*"
  ]
}
~~~

The detector considers any one of these signatures sufficient. This is intentionally specific: searching for any USB hub would be unsafe because the computer may contain internal hubs or unrelated USB devices that do not prove the affected port is working.

If your topology is different, first create a snapshot:

~~~powershell
Get-PnpDevice -PresentOnly |
    Select-Object Status,Class,FriendlyName,InstanceId |
    Export-Csv .\present-devices.csv -NoTypeInformation -Encoding UTF8
~~~

Change the signatures only when you know they belong to the expected USB-C connection.

## Logs and exit codes

The log is stored at:

~~~text
C:\ProgramData\UsbCRecovery\UsbCRecovery.log
~~~

The main script exit codes are:

| Code | Meaning |
| ---: | --- |
| 0 | evidence was found or recovery completed |
| 1 | reset failed or evidence remained absent |
| 2 | missing prerequisite, unavailable UCSI, or unvalidated model |

The script does not retry indefinitely. This is designed to prevent a reset loop during startup.

## Uninstallation

Open PowerShell as Administrator:

~~~powershell
.\scripts\uninstall.ps1
~~~

Uninstallation removes the Scheduled Task and the files under `C:\ProgramData\UsbCRecovery`. If the installer changed `TestInterfaceEnabled`, it attempts to restore the previous value. Review the log before deleting any evidence that may help with diagnosis.

## What was tested

| Intervention | Observed result |
| --- | --- |
| restart Thunderbolt device `8A17` | did not recover |
| restart xHCI controller `8A13` | did not recover |
| restart USB Root Hub | did not recover |
| disable/enable xHCI and Thunderbolt | did not recover |
| restart UCSI device `ACPI\USBC000\0` | did not recover |
| UCSI `PPM_RESET`, `Send 0 1` | did not recover |
| soft UCSI `CONNECTOR_RESET`, `Send 0 10003` | recovered immediately |
| automatic boot check followed by soft `CONNECTOR_RESET` | recovered naturally at boot on 2026-08-09; no reboot/intervention |

The result points to a likely stuck state in the Yoga S740-14IIL connector/Type-C/PD/UCSI/platform-firmware path. It does not prove whether the precise cause belongs to the EC, Type-C/PD controller, Intel platform firmware, Lenovo integration, Windows, or hardware, and it does not establish a universal fix.

## Safety and limitations

- The script runs elevated and may run as `SYSTEM`; treat it as privileged software.
- Resetting may interrupt charging, video, USB, DisplayPort Alt Mode, or an active USB Power Delivery negotiation.
- There is no guarantee that the operation is safe for another laptop, dock, charger, or controller.
- This repository does not distribute `UcsiControl.exe`, drivers, firmware, modified BIOS files, or Microsoft files.
- This project does not include a kernel driver.
- This is not a permanent-fix claim: the reset recovers an observed state but does not modify the firmware.
- If the laptop starts with nothing connected, the absence of known evidence cannot distinguish “healthy port with no device” from “stuck port”; do not install the automation in that scenario without adapting the detector.
- Do not send repeated resets in an attempt to recover hardware showing electrical or physical symptoms.
- Read the code, review the signatures, and keep a recovery path that does not depend on USB-C.

## Compatibility reports

Reports from other Yoga S740 owners are welcome, but they should clearly separate:

1. the exact model and BIOS;
2. Windows version;
3. connected device;
4. UCSI state;
5. `GET_CONNECTOR_STATUS` output;
6. whether the soft reset worked;
7. whether recovery was temporary or persistent.

Do not publish serial numbers, usernames, personal paths, or unreviewed reports.

## Repository structure

~~~text
README.md
README.pt-BR.md
LICENSE
CONTRIBUTING.md
scripts/
  UsbCRecovery.ps1
  diagnose.ps1
  install.ps1
  reset-usbc.ps1
  uninstall.ps1
docs/
  technical-analysis.md
  troubleshooting.md
  how-we-found-it.md
.github/
  ISSUE_TEMPLATE/
    recovery-failed.yml
    same-problem.yml
~~~

## Official references

- [Microsoft: USB-C Connector System Software Interface (UCSI) Driver](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/ucsi)
- [Microsoft: Tools in the MUTT Software Package](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/mutt-software-package)
- [Microsoft: USB Hardware Verifier](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/how-to-retrieve-information-about-a-usb-device)

## License and responsibility

The code in this repository is distributed under the MIT License. Microsoft tools mentioned or used by the user remain subject to Microsoft's licenses and terms.

By running these scripts, you acknowledge that you do so entirely at your own risk. The author and contributors accept no responsibility for data loss, downtime, device damage, registry changes, incompatibility, failed recovery, or any other consequence arising from their use.

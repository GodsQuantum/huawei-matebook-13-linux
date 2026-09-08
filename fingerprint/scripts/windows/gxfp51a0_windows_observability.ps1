[CmdletBinding()]
param(
    [switch]$SkipTrace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host (" " + $Title)
    Write-Host ("=" * 72)
}

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$false)][string[]]$Arguments = @()
    )

    $OutFile = Join-Path $OutDir ($Name + ".txt")
    try {
        $lines = & $FilePath @Arguments 2>&1
        $rc = $LASTEXITCODE
        $lines | Out-File -FilePath $OutFile -Encoding utf8
        "RC=$rc" | Add-Content -Path $OutFile -Encoding utf8
        return @{
            Name = $Name
            Rc = $rc
            Output = $lines
            File = $OutFile
        }
    }
    catch {
        $_ | Out-String | Out-File -FilePath $OutFile -Encoding utf8
        "RC=EXCEPTION" | Add-Content -Path $OutFile -Encoding utf8
        return @{
            Name = $Name
            Rc = -1
            Output = @()
            File = $OutFile
        }
    }
}

function Get-DevicePropertyValue {
    param(
        [string]$InstanceId,
        [string]$KeyName
    )

    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop
        return $p.Data
    }
    catch {
        return $null
    }
}

Write-Section "GXFP51A0 WINDOWS OBSERVABILITY — PASSIVE INVENTORY + OPTIONAL WDF TRACE"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "Run this script from an elevated PowerShell window (Run as administrator)."
    exit 10
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutDir = Join-Path $PSScriptRoot ("gxfp51a0-windows-observability-" + $Stamp)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Summary = Join-Path $OutDir "SUMMARY.txt"

@(
    "GXFP51A0_WINDOWS_OBSERVABILITY"
    "TIMESTAMP=$Stamp"
    "PASSIVE_DEVICE_MUTATION=NONE"
    "DEVICE_DISABLE_ENABLE=NONE"
    "REGISTRY_WRITES=NONE"
    "FIRMWARE_ACTIONS=NONE"
    "GPIO_WRITES=NONE"
    "TRACE_REQUESTED=$(-not $SkipTrace)"
) | Out-File -FilePath $Summary -Encoding utf8

Write-Section "1. OS / TOOLCHAIN MINIMAL INVENTORY"

try {
    $os = Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption, Version, BuildNumber, OSArchitecture
    $os | Format-List | Out-String |
        Out-File (Join-Path $OutDir "os.txt") -Encoding utf8
}
catch {
    $_ | Out-String | Out-File (Join-Path $OutDir "os.txt") -Encoding utf8
}

foreach ($cmd in @("pnputil.exe", "wpr.exe", "tracerpt.exe", "logman.exe", "wevtutil.exe", "reg.exe", "sc.exe")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    "$cmd=$($found.Source)" | Add-Content -Path $Summary -Encoding utf8
}

Write-Section "2. FIND GXFP51A0 PNP DEVICE"

$Devices = @(
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object {
        $_.InstanceId -like "ACPI\GXFP51A0*"
    }
)

if ($Devices.Count -eq 0) {
    "GXFP51A0_PRESENT=NO" | Add-Content -Path $Summary -Encoding utf8
    Write-Error "No present ACPI\GXFP51A0 PnP device was found."
    exit 20
}

"GXFP51A0_PRESENT=YES" | Add-Content -Path $Summary -Encoding utf8
"GXFP51A0_DEVICE_COUNT=$($Devices.Count)" | Add-Content -Path $Summary -Encoding utf8

$Devices |
    Select-Object Status, Class, FriendlyName, InstanceId |
    Format-List |
    Out-String |
    Out-File (Join-Path $OutDir "gx-device-list.txt") -Encoding utf8

$Primary = $Devices[0]
$InstanceId = $Primary.InstanceId

"PRIMARY_INSTANCE_ID=$InstanceId" | Add-Content -Path $Summary -Encoding utf8

Write-Host "GXFP51A0: $InstanceId"

Write-Section "3. PNP PROPERTIES / RESOURCES / STACK"

try {
    Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction Stop |
        Select-Object KeyName, Type, Data |
        ConvertTo-Json -Depth 8 |
        Out-File (Join-Path $OutDir "gx-pnp-properties.json") -Encoding utf8
}
catch {
    $_ | Out-String | Out-File (Join-Path $OutDir "gx-pnp-properties-error.txt") -Encoding utf8
}

$Service = Get-DevicePropertyValue -InstanceId $InstanceId -KeyName "DEVPKEY_Device_Service"
$InfPath = Get-DevicePropertyValue -InstanceId $InstanceId -KeyName "DEVPKEY_Device_DriverInfPath"
$DriverVersion = Get-DevicePropertyValue -InstanceId $InstanceId -KeyName "DEVPKEY_Device_DriverVersion"
$DriverProvider = Get-DevicePropertyValue -InstanceId $InstanceId -KeyName "DEVPKEY_Device_DriverProvider"
$ClassGuid = Get-DevicePropertyValue -InstanceId $InstanceId -KeyName "DEVPKEY_Device_ClassGuid"

"SERVICE=$Service" | Add-Content -Path $Summary -Encoding utf8
"DRIVER_INF=$InfPath" | Add-Content -Path $Summary -Encoding utf8
"DRIVER_VERSION=$DriverVersion" | Add-Content -Path $Summary -Encoding utf8
"DRIVER_PROVIDER=$DriverProvider" | Add-Content -Path $Summary -Encoding utf8
"CLASS_GUID=$ClassGuid" | Add-Content -Path $Summary -Encoding utf8

$PnPUtil = Get-Command pnputil.exe -ErrorAction SilentlyContinue
if ($PnPUtil) {
    Invoke-CapturedCommand `
        -Name "pnputil-gx-full" `
        -FilePath $PnPUtil.Source `
        -Arguments @(
            "/enum-devices",
            "/instanceid", $InstanceId,
            "/services",
            "/stack",
            "/drivers",
            "/interfaces",
            "/properties",
            "/resources"
        ) | Out-Null

    Invoke-CapturedCommand `
        -Name "pnputil-gx-basic" `
        -FilePath $PnPUtil.Source `
        -Arguments @(
            "/enum-devices",
            "/instanceid", $InstanceId
        ) | Out-Null
}

Write-Section "4. DRIVER SERVICE / INF"

if ($Service) {
    $Sc = Get-Command sc.exe -ErrorAction SilentlyContinue
    if ($Sc) {
        Invoke-CapturedCommand -Name "service-qc" -FilePath $Sc.Source -Arguments @("qc", [string]$Service) | Out-Null
        Invoke-CapturedCommand -Name "service-queryex" -FilePath $Sc.Source -Arguments @("queryex", [string]$Service) | Out-Null
    }

    $Reg = Get-Command reg.exe -ErrorAction SilentlyContinue
    if ($Reg) {
        Invoke-CapturedCommand `
            -Name "registry-service" `
            -FilePath $Reg.Source `
            -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Services\$Service", "/s") |
            Out-Null
    }
}

$Reg = Get-Command reg.exe -ErrorAction SilentlyContinue
if ($Reg) {
    Invoke-CapturedCommand `
        -Name "registry-device-enum" `
        -FilePath $Reg.Source `
        -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Enum\$InstanceId", "/s") |
        Out-Null
}

$InfFile = $null
if ($InfPath) {
    $CandidateInf = Join-Path $env:windir ("INF\" + [string]$InfPath)
    if (Test-Path $CandidateInf) {
        $InfFile = $CandidateInf
        Copy-Item -LiteralPath $CandidateInf -Destination (Join-Path $OutDir "gx-driver.inf") -Force

        $InfText = Get-Content -LiteralPath $CandidateInf -Raw -ErrorAction SilentlyContinue
        if ($InfText -match "(?im)^\s*UmdfService\s*=") {
            "WDF_MODEL=UMDF" | Add-Content -Path $Summary -Encoding utf8
        }
        elseif ($InfText -match "(?im)^\s*KmdfService\s*=") {
            "WDF_MODEL=KMDF" | Add-Content -Path $Summary -Encoding utf8
        }
        else {
            "WDF_MODEL=UNRESOLVED_FROM_INF" | Add-Content -Path $Summary -Encoding utf8
        }

        Select-String `
            -LiteralPath $CandidateInf `
            -Pattern "UmdfService","KmdfService","ServiceBinary","AddService","Wdf","WUDF","gfspi","Goodix" `
            -CaseSensitive:$false |
            Out-String |
            Out-File (Join-Path $OutDir "gx-inf-key-lines.txt") -Encoding utf8
    }
}

Write-Section "5. ETW / WPR PROVIDER DISCOVERY"

$ProviderKeywords = "Goodix|GXFP51A0|gfspi|SpbCx|\bSPB\b|\bSPI\b|WDF|Framework|WUDF"

$Wpr = Get-Command wpr.exe -ErrorAction SilentlyContinue
if ($Wpr) {
    $wprProviders = Invoke-CapturedCommand `
        -Name "wpr-providers" `
        -FilePath $Wpr.Source `
        -Arguments @("-providers")

    if ($wprProviders.Output) {
        $wprProviders.Output |
            Select-String -Pattern $ProviderKeywords -CaseSensitive:$false |
            Out-String |
            Out-File (Join-Path $OutDir "wpr-provider-keyword-hits.txt") -Encoding utf8
    }
}
else {
    "WPR_AVAILABLE=NO" | Add-Content -Path $Summary -Encoding utf8
}

$Logman = Get-Command logman.exe -ErrorAction SilentlyContinue
if ($Logman) {
    $logmanProviders = Invoke-CapturedCommand `
        -Name "logman-providers" `
        -FilePath $Logman.Source `
        -Arguments @("query", "providers")

    if ($logmanProviders.Output) {
        $logmanProviders.Output |
            Select-String -Pattern $ProviderKeywords -CaseSensitive:$false |
            Out-String |
            Out-File (Join-Path $OutDir "logman-provider-keyword-hits.txt") -Encoding utf8
    }
}

try {
    Get-NetEventProvider -ShowInstalled -ErrorAction Stop |
        Where-Object {
            $_.Name -match $ProviderKeywords
        } |
        Select-Object Name, Guid |
        Sort-Object Name |
        Format-Table -AutoSize |
        Out-String -Width 240 |
        Out-File (Join-Path $OutDir "netevent-provider-keyword-hits.txt") -Encoding utf8
}
catch {
    $_ | Out-String | Out-File (Join-Path $OutDir "netevent-provider-error.txt") -Encoding utf8
}

Write-Section "6. WDF / PNP / BIOMETRIC EVENT LOG SNAPSHOT"

$Wevt = Get-Command wevtutil.exe -ErrorAction SilentlyContinue
if ($Wevt) {
    $channels = @(
        & $Wevt.Source el 2>$null |
        Where-Object {
            $_ -match "DriverFramework|WDF|Biometric|Kernel-PnP"
        }
    )

    $channels |
        Sort-Object |
        Out-File (Join-Path $OutDir "relevant-event-channels.txt") -Encoding utf8

    $safeIndex = 0
    foreach ($channel in $channels) {
        $safeIndex++
        $safeName = ("eventlog-{0:d2}.txt" -f $safeIndex)
        $dest = Join-Path $OutDir $safeName
        try {
            & $Wevt.Source qe $channel /c:200 /rd:true /f:text 2>&1 |
                Out-File $dest -Encoding utf8
            "CHANNEL=$channel FILE=$safeName" |
                Add-Content (Join-Path $OutDir "eventlog-map.txt") -Encoding utf8
        }
        catch {
            $_ | Out-String | Out-File $dest -Encoding utf8
        }
    }
}

Write-Section "7. WDF ENHANCED-VERIFIER READINESS — DISCOVERY ONLY"

$VerifierCandidates = @()

$cmdVerifier = Get-Command WdfPerfEnhancedVerifier.cmd -ErrorAction SilentlyContinue
if ($cmdVerifier) {
    $VerifierCandidates += $cmdVerifier.Source
}

$KitRoots = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10",
    "$env:ProgramFiles\Windows Kits\10"
) | Where-Object { $_ -and (Test-Path $_) }

foreach ($root in $KitRoots) {
    try {
        $VerifierCandidates += @(
            Get-ChildItem -Path $root -Filter "WdfPerfEnhancedVerifier.cmd" -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -First 10
        )
    }
    catch {
    }
}

$VerifierCandidates = @($VerifierCandidates | Select-Object -Unique)
$VerifierCandidates | Out-File (Join-Path $OutDir "wdf-enhanced-verifier-candidates.txt") -Encoding utf8

"WDF_ENHANCED_VERIFIER_FOUND=$($VerifierCandidates.Count -gt 0)" |
    Add-Content -Path $Summary -Encoding utf8
"WDF_ENHANCED_VERIFIER_EXECUTED=NO" |
    Add-Content -Path $Summary -Encoding utf8

Write-Section "8. OPTIONAL WDF TRACE — NO DEVICE RESTART"

$TraceStarted = $false
$Etl = Join-Path $OutDir "wdf-first-contact.etl"

if ($SkipTrace) {
    "WDF_TRACE=SKIPPED_BY_USER" | Add-Content -Path $Summary -Encoding utf8
}
elseif (-not $Wpr) {
    "WDF_TRACE=SKIPPED_WPR_MISSING" | Add-Content -Path $Summary -Encoding utf8
}
else {
    Write-Host ""
    Write-Host "Attempting the built-in WDF TraceLogging WPR profile."
    Write-Host "No WdfPerfEnhancedVerifier registry change is performed."
    Write-Host ""

    $start = Invoke-CapturedCommand `
        -Name "wpr-wdf-start" `
        -FilePath $Wpr.Source `
        -Arguments @("-start", "WdfTraceLoggingProvider", "-filemode")

    if ($start.Rc -eq 0) {
        $TraceStarted = $true
        "WDF_TRACE_STARTED=YES" | Add-Content -Path $Summary -Encoding utf8

        Write-Host ""
        Write-Host "WDF trace is running."
        Write-Host "Now press Win+L, unlock Windows ONCE with the fingerprint sensor,"
        Write-Host "return to this PowerShell window, then press Enter."
        Write-Host ""

        [void](Read-Host "Press Enter after one Windows fingerprint authentication attempt")

        $stop = Invoke-CapturedCommand `
            -Name "wpr-wdf-stop" `
            -FilePath $Wpr.Source `
            -Arguments @("-stop", $Etl)

        if ($stop.Rc -eq 0 -and (Test-Path $Etl)) {
            "WDF_TRACE_STOPPED=YES" | Add-Content -Path $Summary -Encoding utf8
            "WDF_ETL=$Etl" | Add-Content -Path $Summary -Encoding utf8
        }
        else {
            "WDF_TRACE_STOPPED=ERROR" | Add-Content -Path $Summary -Encoding utf8
        }
    }
    else {
        "WDF_TRACE_STARTED=NO" | Add-Content -Path $Summary -Encoding utf8
    }
}

Write-Section "9. ETL DECODE"

$Tracerpt = Get-Command tracerpt.exe -ErrorAction SilentlyContinue

if ((Test-Path $Etl) -and $Tracerpt) {
    $TraceXml = Join-Path $OutDir "wdf-first-contact-events.xml"
    $TraceSummary = Join-Path $OutDir "wdf-first-contact-tracerpt-summary.txt"
    $TraceReport = Join-Path $OutDir "wdf-first-contact-tracerpt-report.xml"

    Invoke-CapturedCommand `
        -Name "tracerpt-run" `
        -FilePath $Tracerpt.Source `
        -Arguments @(
            $Etl,
            "-o", $TraceXml,
            "-of", "XML",
            "-lr",
            "-summary", $TraceSummary,
            "-report", $TraceReport,
            "-y"
        ) | Out-Null

    if (Test-Path $TraceXml) {
        Select-String `
            -LiteralPath $TraceXml `
            -Pattern $ProviderKeywords `
            -CaseSensitive:$false |
            Select-Object -First 5000 |
            Out-String -Width 320 |
            Out-File (Join-Path $OutDir "wdf-trace-keyword-hits.txt") -Encoding utf8
    }
}

Write-Section "10. SUMMARY ZIP"

$TextBundle = Join-Path $PSScriptRoot ("gxfp51a0-windows-observability-summary-" + $Stamp + ".zip")

$BundleItems = @(
    Get-ChildItem -LiteralPath $OutDir -File |
    Where-Object {
        $_.Extension -ne ".etl"
    } |
    Select-Object -ExpandProperty FullName
)

if ($BundleItems.Count -gt 0) {
    Compress-Archive -Path $BundleItems -DestinationPath $TextBundle -Force
}

"SUMMARY_ZIP=$TextBundle" | Add-Content -Path $Summary -Encoding utf8
"ETL_FILE=$Etl" | Add-Content -Path $Summary -Encoding utf8

Write-Host ""
Write-Host ("=" * 72)
Write-Host " FINAL STATE"
Write-Host ("=" * 72)
Write-Host "GXFP51A0_PRESENT=YES"
Write-Host "PASSIVE_DEVICE_MUTATION=NONE"
Write-Host "REGISTRY_WRITES=NONE"
Write-Host "DEVICE_RESTART=NONE"
Write-Host "FIRMWARE_ACTIONS=NONE"
Write-Host "WDF_ENHANCED_VERIFIER_EXECUTED=NO"
Write-Host "SUMMARY_ZIP=$TextBundle"
if (Test-Path $Etl) {
    Write-Host "WDF_ETL=$Etl"
}
Write-Host "NEXT=UPLOAD_SUMMARY_ZIP_TO_CHAT"

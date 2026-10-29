param([Parameter(Mandatory=$true)][string]$Report,[ValidatePattern('^[0-9A-Fa-f]{4}$')][string]$DeviceId='9038')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($Report)
if($out.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Write inventory outside repository.' }
$DeviceId=$DeviceId.ToUpperInvariant()
$pattern='^PCI\\VEN_10EE&DEV_'+$DeviceId
$devices=@(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match $pattern })
$endpoints=@()
foreach($device in $devices) {
    $properties=@(Get-PnpDeviceProperty -InstanceId $device.InstanceId)
    $link=@($properties | Where-Object { $_.KeyName -match 'PciDevice.*(Link|Speed)' } | ForEach-Object {
        [pscustomobject]@{key=$_.KeyName;value=$_.Data}
    })
    $problem=$properties | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_ProblemCode' } | Select-Object -ExpandProperty Data
    $service=$properties | Where-Object { $_.KeyName -eq 'DEVPKEY_Device_Service' } | Select-Object -ExpandProperty Data
    $drivers=@(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -eq $device.InstanceId } |
        Select-Object DeviceName,DriverProviderName,DriverVersion,InfName,IsSigned)
    $endpoints += [pscustomobject]@{identity=('PCI\VEN_10EE&DEV_'+$DeviceId);name=$device.FriendlyName;status=$device.Status;
        problem_code=$problem;service=$service;link_properties=$link;drivers=$drivers}
}
$result=[pscustomobject]@{observed_at_utc=[DateTime]::UtcNow.ToString('o');os='Windows';
    expected_vendor='10EE';expected_device=$DeviceId;endpoint_count=$devices.Count;
    endpoints=$endpoints;driver_installed_by_this_script=$false;host_dma_tested=$false}
$directory=Split-Path $out -Parent
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding utf8
$result | ConvertTo-Json -Depth 8 -Compress

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RegistryPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'
$script:TargetDirectory = Join-Path $env:WINDIR 'Resources\ShortcutOverlay'
$script:TargetDll = Join-Path $script:TargetDirectory 'blank-resource.dll'
$script:DataDirectory = Join-Path $env:ProgramData 'ShortcutOverlayInstaller'
$script:StateFile = Join-Path $script:DataDirectory 'state.json'
$script:IconReference = "$script:TargetDll,197"
$script:ExpectedHash = '6F4225F21E5A1B567FE3436A7A97CADA5AEA0011C1B415D32EB60B7259D779BC'

Add-Type -Namespace ShortcutOverlay -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern uint ExtractIconEx(string path, int index, System.IntPtr[] large, System.IntPtr[] small, uint count);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool DestroyIcon(System.IntPtr icon);
[System.Runtime.InteropServices.DllImport("shell32.dll")]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@

function Assert-AdminAndUser([string]$ExpectedSid, [string]$ScriptFile) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $exe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedSid "{1}"' -f $ScriptFile, $identity.User.Value
        $child = Start-Process -FilePath $exe -ArgumentList $args -Verb RunAs -Wait -PassThru
        exit $child.ExitCode
    }
    if (-not [Environment]::Is64BitProcess) { throw 'Run the 64-bit PowerShell host.' }
    if ($ExpectedSid -and $ExpectedSid -ne $identity.User.Value) {
        throw 'Elevation used another account. HKCU would target the wrong user. Sign in with an administrator account and retry.'
    }
}

function Assert-NotReparse([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point is not allowed: $Path" }
    }
}

function Assert-Icon([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing DLL: $Path" }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($hash -ne $script:ExpectedHash) { throw "DLL SHA-256 mismatch: $Path" }
    $count = [ShortcutOverlay.Native]::ExtractIconEx($Path, -1, $null, $null, 0)
    if ($count -ne 198) { throw "Expected 198 icons, found $count" }
    $large = [IntPtr[]]::new(1); $small = [IntPtr[]]::new(1)
    try {
        $result = [ShortcutOverlay.Native]::ExtractIconEx($Path, 197, $large, $small, 1)
        if ($result -lt 1 -or $large[0] -eq [IntPtr]::Zero -or $small[0] -eq [IntPtr]::Zero) {
            throw 'Cannot extract icon index 197.'
        }
    } finally {
        foreach ($icon in @($large[0], $small[0])) {
            if ($icon -ne [IntPtr]::Zero) { [void][ShortcutOverlay.Native]::DestroyIcon($icon) }
        }
    }
}

function Open-BaseKey([string]$Hive) {
    $h = if ($Hive -eq 'HKLM') { [Microsoft.Win32.RegistryHive]::LocalMachine } else { [Microsoft.Win32.RegistryHive]::CurrentUser }
    return [Microsoft.Win32.RegistryKey]::OpenBaseKey($h, [Microsoft.Win32.RegistryView]::Registry64)
}

function Get-RegistrySnapshot {
    $result = @()
    foreach ($hive in @('HKLM','HKCU')) {
        $base = Open-BaseKey $hive
        try {
            $key = $base.OpenSubKey($script:RegistryPath, $false)
            $entry = [ordered]@{ Hive=$hive; KeyExisted=($null -ne $key); Values=@() }
            if ($key) {
                try {
                    foreach ($name in @('29','77')) {
                        if ($key.GetValueNames() -contains $name) {
                            $kind = $key.GetValueKind($name).ToString()
                            $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                            if ($kind -eq 'Binary') { $value = [Convert]::ToBase64String([byte[]]$value) }
                            $entry.Values += [ordered]@{ Name=$name; Exists=$true; Kind=$kind; Data=$value }
                        } else {
                            $entry.Values += [ordered]@{ Name=$name; Exists=$false; Kind=$null; Data=$null }
                        }
                    }
                } finally { $key.Close() }
            } else {
                foreach ($name in @('29','77')) { $entry.Values += [ordered]@{ Name=$name; Exists=$false; Kind=$null; Data=$null } }
            }
            $result += $entry
        } finally { $base.Close() }
    }
    return ,$result
}

function Restore-Registry($Snapshots, [bool]$OnlyOurs) {
    $conflicts = @()
    foreach ($entry in $Snapshots) {
        $base = Open-BaseKey $entry.Hive
        try {
            $key = $base.CreateSubKey($script:RegistryPath)
            try {
                foreach ($saved in $entry.Values) {
                    $hasCurrent = $key.GetValueNames() -contains $saved.Name
                    $current = if ($hasCurrent) { $key.GetValue($saved.Name) } else { $null }
                    $owned = $hasCurrent -and ($key.GetValueKind($saved.Name) -eq [Microsoft.Win32.RegistryValueKind]::String) -and
                        [string]::Equals([string]$current, $script:IconReference, [StringComparison]::Ordinal)
                    if ($OnlyOurs -and -not $owned) {
                        $conflicts += "$($entry.Hive) value $($saved.Name)"
                        continue
                    }
                    if (-not $saved.Exists) { $key.DeleteValue($saved.Name, $false); continue }
                    $kind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$saved.Kind)
                    switch ($saved.Kind) {
                        'Binary' { $value = [Convert]::FromBase64String([string]$saved.Data); break }
                        'MultiString' { $value = [string[]]$saved.Data; break }
                        'DWord' { $value = [int]$saved.Data; break }
                        'QWord' { $value = [long]$saved.Data; break }
                        default { $value = [string]$saved.Data }
                    }
                    $key.SetValue($saved.Name, $value, $kind)
                }
            } finally { $key.Close() }
            if (-not $entry.KeyExisted) {
                $check = $base.OpenSubKey($script:RegistryPath, $false)
                if ($check) {
                    try { $empty = ($check.ValueCount -eq 0 -and $check.SubKeyCount -eq 0) }
                    finally { $check.Close() }
                    if ($empty) { $base.DeleteSubKey($script:RegistryPath, $false) }
                }
            }
        } finally { $base.Close() }
    }
    return $conflicts
}

function Set-OurRegistryValues {
    foreach ($hive in @('HKLM','HKCU')) {
        $base = Open-BaseKey $hive
        try {
            $key = $base.CreateSubKey($script:RegistryPath)
            try { foreach ($name in @('29','77')) { $key.SetValue($name, $script:IconReference, [Microsoft.Win32.RegistryValueKind]::String) } }
            finally { $key.Close() }
        } finally { $base.Close() }
    }
}

function Stop-CurrentExplorer {
    $session = (Get-Process -Id $PID).SessionId
    @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session) | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction Stop }
    Start-Sleep -Seconds 2
}

function Start-CurrentExplorer {
    $session = (Get-Process -Id $PID).SessionId
    if (-not @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session).Count) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe')
    }
}

function Refresh-Icons {
    try { [ShortcutOverlay.Native]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero) } catch { Write-Warning $_ }
    $cacheDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    $cacheFiles = @()
    if (Test-Path -LiteralPath $cacheDir) { $cacheFiles += @(Get-ChildItem -LiteralPath $cacheDir -Filter 'iconcache*.db' -File -Force -ErrorAction SilentlyContinue) }
    $legacy = Join-Path $env:LOCALAPPDATA 'IconCache.db'
    if (Test-Path -LiteralPath $legacy) { $cacheFiles += Get-Item -LiteralPath $legacy -Force }
    foreach ($file in $cacheFiles) {
        try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop }
        catch { Write-Warning "Could not clear $($file.FullName). Sign out or restart Windows if icons do not refresh." }
    }
}

function Save-State($State) {
    $tmp = Join-Path $script:DataDirectory 'state.tmp'
    $State | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $script:StateFile -Force
}

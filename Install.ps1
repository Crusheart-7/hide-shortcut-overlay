param([string]$ExpectedSid)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-AdminAndUser $ExpectedSid $PSCommandPath

$sourceDll = Join-Path $PSScriptRoot 'blank-resource.dll'
$explorerStopped = $false
$fileTouched = $false
$registryTouched = $false
$state = $null
try {
    Assert-Icon $sourceDll
    Assert-NotReparse $script:DataDirectory
    Assert-NotReparse $script:TargetDirectory
    Assert-NotReparse $script:TargetDll
    if ((Test-Path -LiteralPath $script:DataDirectory) -and -not (Test-Path -LiteralPath $script:DataDirectory -PathType Container)) { throw 'State path is not a directory.' }
    if ((Test-Path -LiteralPath $script:TargetDirectory) -and -not (Test-Path -LiteralPath $script:TargetDirectory -PathType Container)) { throw 'Target folder path is not a directory.' }
    if ((Test-Path -LiteralPath $script:TargetDll) -and -not (Test-Path -LiteralPath $script:TargetDll -PathType Leaf)) { throw 'Target DLL path is not a file.' }
    New-Item -ItemType Directory -Path $script:DataDirectory -Force | Out-Null
    $acl = Get-Acl -LiteralPath $script:DataDirectory
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($existingRule in @($acl.Access)) { [void]$acl.RemoveAccessRuleSpecific($existingRule) }
    foreach ($sid in @('S-1-5-32-544','S-1-5-18')) {
        $account = [Security.Principal.SecurityIdentifier]::new($sid)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($account, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $script:DataDirectory -AclObject $acl
    if (Test-Path -LiteralPath $script:StateFile) {
        $previous = Get-Content -LiteralPath $script:StateFile -Raw | ConvertFrom-Json
        if ($previous.Status -ne 'Uninstalled' -and $previous.Status -ne 'RolledBack') {
            throw "Existing installation state is $($previous.Status). Run Uninstall.cmd first."
        }
    }
    $backupName = 'backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N')
    $backupDir = Join-Path $script:DataDirectory $backupName
    New-Item -ItemType Directory -Path $backupDir | Out-Null
    $snapshots = Get-RegistrySnapshot
    foreach ($entry in $snapshots) {
        if ($entry.KeyExisted) {
            $sourceKey = "$($entry.Hive)\$script:RegistryPath"
            & (Join-Path $env:WINDIR 'System32\reg.exe') export $sourceKey (Join-Path $backupDir "$($entry.Hive)-ShellIcons.reg") /y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Registry export failed: $sourceKey" }
        }
    }
    $originalExists = Test-Path -LiteralPath $script:TargetDll -PathType Leaf
    $originalHash = $null
    if ($originalExists) {
        $originalHash = (Get-FileHash -LiteralPath $script:TargetDll -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $script:TargetDll -Destination (Join-Path $backupDir 'original-blank-resource.dll') -ErrorAction Stop
        if ((Get-FileHash -LiteralPath (Join-Path $backupDir 'original-blank-resource.dll') -Algorithm SHA256).Hash -ne $originalHash) {
            throw 'Original DLL backup verification failed.'
        }
    }
    $state = [ordered]@{
        Version=1; Status='Pending'; Created=(Get-Date).ToString('o'); UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        BackupName=$backupName; OriginalDllExisted=$originalExists; OriginalDllHash=$originalHash
        PackageHash=$script:ExpectedHash; Registry=$snapshots
    }
    Save-State $state
    New-Item -ItemType Directory -Path $script:TargetDirectory -Force | Out-Null
    Stop-CurrentExplorer
    $explorerStopped = $true
    $fileTouched = $true
    Copy-Item -LiteralPath $sourceDll -Destination $script:TargetDll -Force -ErrorAction Stop
    Assert-Icon $script:TargetDll
    $registryTouched = $true
    Set-OurRegistryValues
    Refresh-Icons
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Common.ps1') -Destination (Join-Path $script:DataDirectory 'Common.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination (Join-Path $script:DataDirectory 'Uninstall.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.cmd') -Destination (Join-Path $script:DataDirectory 'Uninstall.cmd') -Force
    $state.Status = 'Active'
    Save-State $state
    Write-Host 'Installed. Explorer will restart. If an overlay remains cached, sign out and back in.'
} catch {
    Write-Warning "Installation failed: $_"
    if ($state) {
        try {
            if (($fileTouched -or $registryTouched) -and -not $explorerStopped) { Stop-CurrentExplorer; $explorerStopped = $true }
            if ($registryTouched) { [void](Restore-Registry $state.Registry $false) }
            if ($fileTouched) {
                if ($state.OriginalDllExisted) {
                    $backup = Join-Path (Join-Path $script:DataDirectory $state.BackupName) 'original-blank-resource.dll'
                    Copy-Item -LiteralPath $backup -Destination $script:TargetDll -Force
                } elseif (Test-Path -LiteralPath $script:TargetDll) {
                    Remove-Item -LiteralPath $script:TargetDll -Force
                }
            }
            if ($fileTouched -or $registryTouched) { Refresh-Icons }
            $state.Status = 'RolledBack'
            Save-State $state
            Write-Host 'Original registry values and DLL restored.'
        } catch {
            $state.Status = 'RecoveryRequired'
            try { Save-State $state } catch { }
            Write-Warning "Automatic rollback failed: $_. Backups are in $script:DataDirectory"
        }
    }
    exit 1
} finally {
    if ($explorerStopped) {
        try { Start-CurrentExplorer } catch { Write-Warning "Could not restart Explorer: $_. Start explorer.exe or sign out and back in." }
    }
}

param([string]$ExpectedSid)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-AdminAndUser $ExpectedSid $PSCommandPath

$explorerStopped = $false
$state = $null
try {
    Assert-NotReparse $script:DataDirectory
    Assert-NotReparse $script:TargetDirectory
    Assert-NotReparse $script:TargetDll
    if ((Test-Path -LiteralPath $script:TargetDll) -and -not (Test-Path -LiteralPath $script:TargetDll -PathType Leaf)) { throw 'Target DLL path is not a file.' }
    if (-not (Test-Path -LiteralPath $script:StateFile)) { throw 'No installation state found. Nothing to restore automatically.' }
    $state = Get-Content -LiteralPath $script:StateFile -Raw | ConvertFrom-Json
    if ($state.Status -eq 'Uninstalled' -or $state.Status -eq 'RolledBack') { Write-Host 'Already restored.'; exit 0 }
    if ($state.Version -ne 1 -or $state.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        throw 'State version or user account differs. Refusing to alter HKCU.'
    }
    if ($state.BackupName -notmatch '^backup-[0-9]{8}-[0-9]{6}-[0-9a-f]{32}$') { throw 'Invalid backup location in state.' }
    $backupDir = Join-Path $script:DataDirectory $state.BackupName
    Assert-NotReparse $backupDir
    $backup = Join-Path $backupDir 'original-blank-resource.dll'
    if ($state.OriginalDllExisted) {
        Assert-NotReparse $backup
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw 'Original DLL backup is missing.' }
        if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $state.OriginalDllHash) { throw 'Original DLL backup hash mismatch.' }
    }
    Stop-CurrentExplorer
    $explorerStopped = $true
    $conflicts = @(Restore-Registry $state.Registry $true)
    if (Test-Path -LiteralPath $script:TargetDll -PathType Leaf) {
        $currentHash = (Get-FileHash -LiteralPath $script:TargetDll -Algorithm SHA256).Hash
        if ($currentHash -eq $state.PackageHash) {
            if ($state.OriginalDllExisted) { Copy-Item -LiteralPath $backup -Destination $script:TargetDll -Force }
            else { Remove-Item -LiteralPath $script:TargetDll -Force }
        } else { $conflicts += 'DLL changed since installation' }
    } else { $conflicts += 'DLL removed since installation' }
    Refresh-Icons
    if ($conflicts.Count) {
        $state.Status = 'Partial'
        Save-State $state
        Write-Warning ('Skipped changed items: ' + ($conflicts -join ', '))
        Write-Host "Backups remain in $backupDir"
        exit 2
    }
    $state.Status = 'Uninstalled'
    Save-State $state
    Write-Host "Restored original registry values and DLL. Backups remain in $backupDir"
} catch {
    Write-Warning "Uninstall failed: $_"
    if ($state) {
        try { $state.Status = 'RecoveryRequired'; Save-State $state } catch { }
        Write-Host "Backups remain in $script:DataDirectory"
    }
    exit 1
} finally {
    if ($explorerStopped) {
        try { Start-CurrentExplorer } catch { Write-Warning "Could not restart Explorer: $_. Start explorer.exe or sign out and back in." }
    }
}

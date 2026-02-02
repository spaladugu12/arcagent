# Install-Script.ps1
$ErrorActionPreference = "Stop"
# ----- helper: reboot pending / servicing gate -----
function Test-RebootPending {
 if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return $true }
 if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return $true }
 $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
       -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
 return [bool]$p.PendingFileRenameOperations
}
function Wait-ForWindowsReady {
 param([int]$TimeoutSeconds = 900)
 $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
 while((Get-Date) -lt $deadline) {
   $msiBusy = Get-Process msiexec -ErrorAction SilentlyContinue
   $tiBusy  = Get-Process TrustedInstaller -ErrorAction SilentlyContinue
   $rp      = Test-RebootPending
   if (-not $msiBusy -and -not $tiBusy -and -not $rp) {
     Write-Host "Windows looks ready (no msiexec, no TrustedInstaller, no reboot pending)."
     return
   }
   Write-Host "Waiting... msiexec=$([bool]$msiBusy) TrustedInstaller=$([bool]$tiBusy) rebootPending=$rp"
   Start-Sleep -Seconds 15
 }
 throw "Windows not ready within timeout ($TimeoutSeconds sec)."
}
# ----- start logging so you can debug later -----
New-Item -ItemType Directory -Force -Path "C:\Temp" | Out-Null
Start-Transcript -Path "C:\Temp\ArcInstall-Transcript.txt" -Append
Write-Host "=== Arc install started: $(Get-Date) ==="
# ----- REQUIRED: these must be passed in via commandToExecute -----
param(
 [Parameter(Mandatory=$true)][string]$appId,
 [Parameter(Mandatory=$true)][string]$password,
 [Parameter(Mandatory=$true)][string]$tenantId,
 [Parameter(Mandatory=$true)][string]$subscriptionId,
 [Parameter(Mandatory=$true)][string]$resourceGroup,
 [Parameter(Mandatory=$true)][string]$location
)
# ----- wait for OS readiness -----
Wait-ForWindowsReady -TimeoutSeconds 1200
# ----- download MSI -----
$msiUrl  = "https://aka.ms/AzureConnectedMachineAgent"
$msiPath = "C:\Temp\AzureConnectedMachineAgent.msi"
$logPath = "C:\Windows\Temp\ArcAgentInstall.log"
$agentExe = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"
Write-Host "Downloading Arc agent MSI..."
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
if (-not (Test-Path $msiPath)) { throw "MSI download failed: $msiPath" }
# ----- install MSI -----
Write-Host "Installing Arc agent MSI..."
$proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$msiPath`" /qn /norestart /l*v `"$logPath`""
Write-Host "MSI exit code: $($proc.ExitCode)"
if ($proc.ExitCode -notin 0,3010) {
 Write-Host "MSI failed. Log tail:"
 Get-Content $logPath -Tail 150 | Write-Host
 throw "Arc MSI install failed with exit code $($proc.ExitCode)"
}
# ----- verify install -----
if (-not (Test-Path $agentExe)) {
 Write-Host "Agent exe not found. MSI log tail:"
 Get-Content $logPath -Tail 150 | Write-Host
 throw "azcmagent.exe not found at $agentExe after install."
}
# ----- connect -----
Write-Host "Connecting Arc agent..."
& $agentExe connect `
 --service-principal-id $appId `
 --service-principal-secret $password `
 --tenant-id $tenantId `
 --subscription-id $subscriptionId `
 --resource-group $resourceGroup `
 --location $location
Write-Host "Arc connect completed. azcmagent show:"
& $agentExe show | Out-Host
Write-Host "=== Arc install finished successfully: $(Get-Date) ==="
Stop-Transcript
exit 0

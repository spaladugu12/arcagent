param(
 [Parameter(Mandatory=$true)][string]$appId,
 [Parameter(Mandatory=$true)][string]$password,
 [Parameter(Mandatory=$true)][string]$tenantId,
 [Parameter(Mandatory=$true)][string]$subscriptionId,
 [Parameter(Mandatory=$true)][string]$resourceGroup,
 [Parameter(Mandatory=$true)][string]$location
)
$ErrorActionPreference = "Stop"
# logging
New-Item -ItemType Directory -Force -Path "C:\Temp" | Out-Null
Start-Transcript -Path "C:\Temp\ArcInstall-Transcript.txt" -Append
function Test-RebootPending {
 if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return $true }
 if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return $true }
 $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
 return [bool]$p.PendingFileRenameOperations
}
function Wait-ForWindowsReady {
 param([int]$TimeoutSeconds = 1200)
 $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
 while((Get-Date) -lt $deadline) {
   $msiBusy = Get-Process msiexec -ErrorAction SilentlyContinue
   $tiBusy  = Get-Process TrustedInstaller -ErrorAction SilentlyContinue
   $rp      = Test-RebootPending
   if (-not $msiBusy -and -not $tiBusy -and -not $rp) { return }
   Start-Sleep -Seconds 15
 }
 throw "Windows not ready within timeout."
}
# ---- main ----

$msiUrl  = "https://aka.ms/AzureConnectedMachineAgent"
$msiPath = "C:\Temp\AzureConnectedMachineAgent.msi"
$logPath = "C:\Windows\Temp\ArcAgentInstall.log"
$agentExe = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
$proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$msiPath`" /qn /norestart /l*v `"$logPath`""
if ($proc.ExitCode -notin 0,3010) {
 Get-Content $logPath -Tail 150 | Write-Host
 throw "Arc MSI install failed with exit code $($proc.ExitCode)"
}
if (-not (Test-Path $agentExe)) { throw "azcmagent.exe not found at $agentExe after install." }
& $agentExe connect `
 --service-principal-id $appId `
 --service-principal-secret $password `
 --tenant-id $tenantId `
 --subscription-id $subscriptionId `
 --resource-group $resourceGroup `
 --location $location
& $agentExe show | Out-Host
Stop-Transcript
exit 0


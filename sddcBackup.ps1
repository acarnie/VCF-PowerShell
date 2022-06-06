# ====================================================================================
#       VMware Cloud Foundation Configure SDDC Manager and NSX-T Manager Backup               
#                                                                                    
#  You must have PowerVCF and PowerCLI Modules installed in order to use this script     
#                                                                                    
#                   Words and Music By Ben Sier and Alasdair Carnie                      
# ====================================================================================

# Variables for the execution log file and json file directories.
$scriptDir = Split-Path $MyInvocation.MyCommand.Path # Log file diretories will be created in the folder you exeute the script from
$logPathDir = New-Item -ItemType Directory -Path "$scriptDir\Logs" -Force
$jsonPathDir = New-Item -ItemType Directory -Path "$scriptDir\json" -Force
$logfile = "$logPathDir\VVS-Log-_$(get-date -format `"yyyymmdd_hhmmss`").txt"

# Custom function to create a separate logging window for script execution.
Function logger($strMessage, [switch]$logOnly,[switch]$consoleOnly)
{
	$curDateTime = get-date -format "hh:mm:ss"
	$entry = "$curDateTime :> $strMessage"
    if ($consoleOnly) {
		write-host $entry
    } elseif ($logOnly) {
		$entry | out-file -Filepath $logfile -append
	} else {
        write-host $entry
		$entry | out-file -Filepath $logfile -append
	}
}

Logger "Configure the backup settings for SDDC Manager and NSX-T Manager"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager variables
$sddcManagerfqdn = "cmi-vcf01.elasticsky.org"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!"
$sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!"

# Authenticate to SDDC Manager using global variables defined at the top of the script
Request-VCFToken -fqdn $sddcManagerfqdn -username $ssoUser -password $ssoPass

Start-Sleep 5

# Variables for configuring the SDDC Manager and NSX-T Manager Backups
logger "Create variables and extract SSH Key for Backup User"

$backupServer = "10.0.0.221"
$backupPort = "22"
$backupPath = "/home/admin"
$backupUser = "admin"
$backupPassword = "VMware123!"
$backupProtocol = "SFTP"
$backupPassphrase = "VMware123!VMware123!"
$vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters

connect-viserver -server $vcenter.fqdn -user $ssoUser -password $ssoPass
$getKeyCommand = "ssh-keygen -lf <(ssh-keyscan $backupServer 2>/dev/null) | grep '2048 SHA256'"
$keyCommandResult = Invoke-VMScript -ScriptType bash -GuestUser $sddcUser -GuestPassword $sddcPassword -VM $sddcMgrVMName -ScriptText $getKeyCommand
$backupKey = $($keyCommandResult.Split()[1])

# Create the PSObject for backup configuration
logger "Create backup configuration JSON specification"
$backUpConfigurationSpec = [PSCustomObject]@{

    backupLocations = @(@{server = $backupServer; username = $backupUser; password = $backupPassword; port = $backupPort; protocol = $backupProtocol; directoryPath = $backupPath; sshFingerprint = $backupKey })
    backupSchedules = @(@{frequency = 'HOURLY'; resourceType = 'SDDC_MANAGER'; minuteOfHour = '0' })
    encryption      = @{passphrase = $backupPassphrase }

}

# Creating Backup Config JSON file from the PSObject
logger "Creating Backup Config JSON file"
$backUpConfigurationSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\backUpConfigurationSpec.json

# Configuring SDDC Manager Backup settings
logger "Configuring SDDC Manager Backup Settings"
$confVcfBackup = Set-VCFBackupConfiguration -json $($backUpConfigurationSpec | ConvertTo-Json -Depth 10)
do { $taskStatus = Get-VCFTask -id $($confVcfBackup.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

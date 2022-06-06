# ====================================================================================
#               Deploy new VI Workload Doamin
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

Logger "Deploying MGMT WLD Edge Cluster and AVN Configuration"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager variables
logger "Creating SDDC Manager variables"
$sddcManagerfqdn = "cmi-vcf01.elasticsky.org"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!"
$sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!"

# Authenticate to SDDC Manager using global variables defined at the top of the script
logger "Authenticating with SDDC Manager"
Request-VCFToken -fqdn $sddcManagerfqdn -username $ssoUser -password $ssoPass

Start-Sleep 5

# Get the management cluster ID from SDDC Manager and store it in a variable
logger "Get the first three available hosts"
$availableHosts = $(Get-VCFHost | Where-Object {$_.status -match "UNASSIGNED_USEABLE"} | Select-Object -ExpandProperty id -First 3)

logger "Getting default VI Workload Domain Configuration file and populating the Host Id"
# Get the NSX Edge Cluster config and convert it from JSON to a PSObject, then store it in a variable
$wldPayload = $(get-content "$scriptdir\json\WLD_DOMAIN_API.json" | ConvertFrom-JSON)
$hstCnt = 0
$wldPayload.computeSpec.clusterSpecs.hostSpecs | Foreach {$_.id = $availableHosts[$hstCnt];$hstCnt++}

logger "Writing new VI Workload Domain Configuration file"
# convert the PSObject to a JSON file and save it as a new JSON
$($wldPayload | ConvertTo-JSON -Depth 10) | Out-File "$scriptDir\json\VIWLD.json"

logger "Deploying Edge Cluster"
$edgeDeploy = New-VCFWorkloadDomain -json "$scriptDir\json\VIWLD.json"
do { $taskStatus = Get-VCFTask -id $($edgeDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
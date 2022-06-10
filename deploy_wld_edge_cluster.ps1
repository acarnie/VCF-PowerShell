# ====================================================================================
#               Deploy new Management Edge Cluster and AVN Configuration
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

# Get the VI Workload Domain cluster ID from SDDC Manager and store it in a variable
logger "Geting the management vSphere cluster ID"
$sddcClusterid = $(get-vcfworkloaddomain | Where-Object { $_.type -match "VI" } | Select-Object -ExpandProperty clusters).id

logger "Getting default Edge CLuster JSON Configuration file and populating clusterId"
# Get the VI WLD NSX Edge Cluster config and convert it from JSON to a PSObject, then store it in a variable
$edgeClusterPayload = $(get-content "$scriptdir\NSX_EdgeCluster_API_WLD.json" | ConvertFrom-JSON)

# Find all entries for Cluster ID and replace the existing entry with the management cluster ID
$edgeClusterPayload.edgeNodeSpecs | ForEach-Object {$_.clusterID = $sddcClusterId}

logger "Writing new Edge Cluster Configuration file"
# convert the PSObject to a JSON file and save it as a new JSON
$($edgeClusterPayload | ConvertTo-JSON -Depth 10) | Out-File "$scriptDir\WLD_Edge_Cluster.json"

logger "Deploying Edge Cluster"
$edgeDeploy = New-VCFEdgeCluster -json "$scriptDir\WLD_Edge_Cluster.json"
do { $taskStatus = Get-VCFTask -id $($edgeDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

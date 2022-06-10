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

# Get the management cluster ID from SDDC Manager and store it in a variable
logger "Geting the management vSphere cluster ID"
$sddcClusterid = $(get-vcfworkloaddomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty clusters).id

logger "Getting default Edge CLuster JSON Configuration file and populating clusterId"
# Get the NSX Edge Cluster config and convert it from JSON to a PSObject, then store it in a variable
$edgeClusterPayload = $(get-content "$scriptdir\NSX_Edge_Cluster.json" | ConvertFrom-JSON)

# Find all entries for Cluster ID and replace the existing entry with the management cluster ID
$edgeClusterPayload.edgeNodeSpecs | ForEach-Object {$_.clusterID = $sddcClusterId}

logger "Writing new Edge Cluster Configuration file"
# convert the PSObject to a JSON file and save it as a new JSON
$($edgeClusterPayload | ConvertTo-JSON -Depth 10) | Out-File "$scriptDir\json\MGMT_Edge_Cluster.json"

logger "Deploying Edge Cluster"
$edgeDeploy = New-VCFEdgeCluster -json "$scriptDir\json\MGMT_Edge_Cluster.json"
do { $taskStatus = Get-VCFTask -id $($edgeDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

# Get the Edge Cluster ID
logger "Getting Edge Cluster ID"
$edgeClusterId = Get-VCFEdgeCluster | Select-Object -ExpandProperty id

#Create AVN Configration JSON file
logger"Creating AVN Configuration JSON file"
$avnjson = [PSCustomObject]@{
    avns= @(@{gateway = '10.50.0.1';mtu= '8000';name= 'region-seg01';regionType= 'REGION_A';routerName= 'cmi-m01-ec01-t1-gw01';subnet= '10.50.0.0'; subnetMask= '255.255.255.0' }
          @{gateway= '10.60.0.1';mtu= '8000';name= 'xreg-seg01';regionType= 'X_REGION';routerName= 'cmi-m01-ec01-t1-gw01';subnet= '10.60.0.0'; subnetMask= '255.255.255.0' })
    edgeClusterId = $edgeClusterId
}

$avnjson | ConvertTo-Json -Depth 10 | Out-File "$scriptDir\json\avns.json"

#Deploy the S]AVN Configuration
logger "Configuring the Edge Cluster with AVN Segments"
$avnDeploy = Add-VCFApplicationVirtualNetwork  -json "$scriptDir\json\avns.json"
do { $taskStatus = Get-VCFTask -id $($avnDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
logger "AVN Configuration deployed successfully"
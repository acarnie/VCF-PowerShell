# ====================================================================================
#                 VMware Cloud Foundation Post BringUp Configuration                 
#                                                                                    
#      You must have PowerVCF and PowerCLI installed in order to use this script     
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

logger "VCF Certificate Configuration.  Brought to you by the letters L and F, and by the number 42"

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

# ==================== Configure Microsoft Certificate Authority Integration, and create and deploy certificates for vCenter, NSX-T and SDDC Manager ====================

# Variables for adding the CA to SDDC Manager
$mscaUrl = "https://es-dc-01.elasticsky.org/certsrv"
$mscaUser = "svc-vcf-ca@elasticsky.org"
$mscaPassword = "VMware123!"

# Register Microsoft CA with SDDC Manager
logger "Register Microsoft CA with SDDC Manager"
Set-VCFMicrosoftCA -serverUrl $mscaUrl -username $mscaUser -password $mscaPassword -templateName VMware

Start-Sleep 5

# Create Certificate Variables
logger "Create Certificate Variables"

$domainName = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty name
$vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters
$vcenter | Add-Member -Type NoteProperty -Name Type -Value "VCENTER"
$nsxTCluster = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty nsxtCluster
$nsxTCluster | Add-Member -MemberType NoteProperty -Name Type -Value "NSXT_MANAGER"
$sddcCertManager = Get-VCFManager | Select-Object id, fqdn
$sddcCertManager | Add-Member -MemberType NoteProperty -Name Type -Value "SDDC_MANAGER"

$country = "us"
$keySize = "2048"
$keyAlg = "RSA"
$locality = "Champaign"
$org = "ElasticSky"
$orgUnit = "IT"
$state = "IL"
$email = "administrator@elasticsky.org"

# Create the JSON file for CSR Generation.  Note.  This uses the original method of constructing a PSObject.
logger "Creating JSON file for CSR request in $domainName"
$csrsGenerationSpec = New-Object -TypeName PSCustomObject 
$csrsGenerationSpec | Add-Member -NotePropertyName csrGenerationSpec -NotePropertyValue @{country = $country; email = $email; keyAlgorithm = $keyAlg; keySize = $keySize; locality = $locality; organization = $org; organizationUnit = $orgUnit; state = $state }
$csrsGenerationSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vcenter.fqdn; name = $vcenter.fqdn; sans = @($vcenter.fqdn); resourceID = $vcenter.id; type = $vcenter.type }, @{fqdn = $nsxTCluster.vipfqdn; name = $nsxTCluster.vipfqdn; sans = @($nsxTCluster.vip, $nsxTCluster.vipfqdn); resourceID = $nsxTCluster.id; type = $nsxTCluster.type }, @{fqdn = $sddcCertManager.fqdn; name = $sddcCertManager.fqdn; sans = @($sddcCertManager.fqdn); resourceID = $sddcCertManager.id; type = $sddcCertManager.type })

$csrsGenerationSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\csrsGenerationSpec.json

Start-Sleep 5

# Create CSRs for vCenter, NSX-T and SDDC Manager
logger "Requesting CSR's for $domainName"
$csrReq = Request-VCFCertificateCSR -domainName $domainName -json $jsonPathDir\csrsGenerationSpec.json
do { $taskStatus = Get-VCFTask -id $($csrReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

# Create JSON Spec for requesting certificates
logger "Creating JSON spec for certificate creation in $domainName"
$certCreateSpec = New-Object -TypeName PSCustomObject 
$certCreateSpec | Add-Member -NotePropertyName caType -NotePropertyValue "Microsoft"
$certCreateSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vcenter.fqdn; name = $vcenter.fqdn; sans = @($vcenter.fqdn); resourceID = $vcenter.id; type = $vcenter.type }, @{fqdn = $nsxTCluster.vipfqdn; name = $nsxTCluster.vipfqdn; sans = @($nsxTCluster.vip, $nsxTCluster.vipfqdn); resourceID = $nsxTCluster.id; type = $nsxTCluster.type }, @{fqdn = $sddcCertManager.fqdn; name = $sddcCertManager.fqdn; sans = @($sddcCertManager.fqdn); resourceID = $sddcCertManager.id; type = $sddcCertManager.type })

$certCreateSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certCreateSpec.json

# Request the creation of certificates for vCenter, NSX-T and SDDC Manager
logger "Generating Certs on CA for $domainName"
$certCreateReq = Request-VCFCertificate -domainName $domainName -json $jsonPathDir\certCreateSpec.json
do { $taskStatus = Get-VCFTask -id $($certCreateReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")


# Create JSON Spec for installing certificates
logger "Creating JSON Spec for installing certificates"
$certInstallSpec = New-Object -TypeName PSCustomObject
$certInstallSpec | Add-Member -NotePropertyName operationType -NotePropertyValue "INSTALL"
$certInstallSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vcenter.fqdn; name = $vcenter.fqdn; sans = @($vcenter.fqdn); resourceID = $vcenter.id; type = $vcenter.type }, @{fqdn = $nsxTCluster.vipfqdn; name = $nsxTCluster.vipfqdn; sans = @($nsxTCluster.vip, $nsxTCluster.vipfqdn); resourceID = $nsxTCluster.id; type = $nsxTCluster.type }, @{fqdn = $sddcCertManager.fqdn; name = $sddcCertManager.fqdn; sans = @($sddcCertManager.fqdn); resourceID = $sddcCertManager.id; type = $sddcCertManager.type })

$certInstallSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certInstallSpec.json

# Install certificates on vCenter, NSX-T and SDDC Manager
logger "Installing Certificates for $domainName"
$certInstallReq = Set-VCFCertificate -domainName $domainName -json $jsonPathDir\certInstallSpec.json
do { $taskStatus = Get-VCFTask -id $($certInstallReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

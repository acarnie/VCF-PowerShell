# ====================================================================================
#                 VMware Cloud Foundation Post BringUp Configuration                 
#                                                                                    
#      You must have PowerVCF and PowerCLI installed in order to use this script     
#                                                                                    
#                   Words and Music By Ben Sier and Alasdair Carnie                      
# ====================================================================================

# Import Required PowerShell Modules
Import-Module PowerVCF
Import-Module VMware.PowerCLI

# Create the global variables
$global:scriptDir = Split-Path $MyInvocation.MyCommand.Path
$global:sddcManagerfqdn = "cmi-vcf01.elasticsky.org"
$global:ssoUser = "administrator@vsphere.local"
$global:ssoPass = "VMware123!"
$global:sddcMgrVMName = "cmi-vcf01"
$global:sddcUser = "root"
$global:sddcPassword = "VMware123!"


# Variables for the log file and json file location.  The directories will be automatically created in the directory you execute the script from.
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

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

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

$country = "us"
$keySize = "2048"
$keyAlg = "RSA"
$locality = "Champaign"
$org = "ElasticSky"
$orgUnit = "IT"
$state = "IL"
$email = "administrator@elasticsky.org"

$domainName = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty name
$vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters
$vcenter | Add-Member -Type NoteProperty -Name Type -Value "VCENTER"

$nsxTCluster = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty nsxtCluster
$nsxTCluster | Add-Member -MemberType NoteProperty -Name Type -Value "NSXT_MANAGER"

$sddcCertManager = Get-VCFManager | Select-Object id, fqdn
$sddcCertManager | Add-Member -MemberType NoteProperty -Name Type -Value "SDDC_MANAGER"

# Create the JSON file for CSR Generation
logger "Creating JSON file for CSR request in $domainName"
$csrsGenerationSpec = New-Object -TypeName PSCustomObject 
$csrsGenerationSpec | Add-Member -NotePropertyName csrGenerationSpec -NotePropertyValue @{country = $country; email = $email; keyAlgorithm = $keyAlg; keySize = $keySize; locality = $locality; organization = $org; organizationUnit = $orgUnit; state = $state }
$csrsGenerationSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vcenter.fqdn; name = $vcenter.fqdn; sans = @($vcenter.fqdn); resourceID = $vcenter.id; type = $vcenter.type }, @{fqdn = $nsxTCluster.vipfqdn; name = $nsxTCluster.vipfqdn; sans = @($nsxTCluster.vip, $nsxTCluster.vipfqdn); resourceID = $nsxTCluster.id; type = $nsxTCluster.type }, @{fqdn = $sddcCertManager.fqdn; name = $sddcCertManager.fqdn; sans = @($sddcCertManager.fqdn); resourceID = $sddcCertManager.id; type = $sddcCertManager.type })

$csrsGenerationSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\csrsGenerationSpec.json

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

# ==================== Configure SDDC Manager Backup ====================

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


logger "Create backup configuration JSON specification"
$backUpConfigurationSpec = [PSCustomObject]@{

    backupLocations = @(@{server = $backupServer; username = $backupUser; password = $backupPassword; port = $backupPort; protocol = $backupProtocol; directoryPath = $backupPath; sshFingerprint = $backupKey })
    backupSchedules = @(@{frequency = 'HOURLY'; resourceType = 'SDDC_MANAGER'; minuteOfHour = '0' })
    encryption      = @{passphrase = $backupPassphrase }

}

# Creating Backup Config JSON file
logger "Creating Backup Config JSON file"
$backUpConfigurationSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\backUpConfigurationSpec.json

# Configuring SDDC Manager Backup settings
logger "Configuring SDDC Manager Backup Settings"
$confVcfBackup = Set-VCFBackupConfiguration -json $($backUpConfigurationSpec | ConvertTo-Json -Depth 10)
do { $taskStatus = Get-VCFTask -id $($confVcfBackup.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")


# ==================== Configure Repository ====================

# Variables for configuring the SDDC Manager Depot
$depotUser = "user@company.com"
$depotPassword = "P@ssW0rd"

# NOTE:  The changes to the base images and poll interval are for demonstration purposes, and should only be changed after you have consulted with your customer regarding upgrades to any existing VCF deployments
logger "Creating Script to Modify Default LCM Settings for Base Bundle and Polling Interval"
$lcmChangeScript += "sed -i 's/lcm.core.manifest.poll.interval=300000/lcm.core.manifest.poll.interval=120000/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vrslcm.install.base.version=8.1.0-16776528/vrslcm.install.base.version=8.4.1-18537943/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vra.install.base.version=8.1.0-15986821/vra.install.base.version=8.5.0-18472703/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vrops.install.base.version=8.1.1-16522874/vrops.install.base.version=8.5.0-18255622/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vrli.install.base.version=8.1.1-16281169/vrli.install.base.version=8.4.1-18136317/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "echo wsa.install.base.version=3.3.5-18049997 >> /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "systemctl restart lcm`n"
$lcmChangeScript += "systemctl status lcm | grep Active`n"
logger "Writing Changes to SDDC Manager Lifecycle Manager and Restarting LCM Service"
Invoke-VMScript -ScriptType bash -GuestUser $sddcUser -GuestPassword $sddcPassword -VM $sddcMgrVMName -ScriptText $lcmChangeScript

Start-Sleep 25

# Set Depot credentials in SDDC Manager
logger "Set the Bundle Depot Credentials in SDDC Manager"
Set-VCFDepotCredential -username $depotUser -password $depotPassword

Start-Sleep 600

# ==================== Check for the existance of AVNs and create them if required =======================

# Variables to check for the existance of AVNs, and to create them if required.
$avnsLocalGw = "10.50.0.1"
$avnsLocalMtu = "8000"
$avnsLocalName = "region-seg-1"
$avnsLocalRegionType = "REGION_A"
$avnsLocalRouterName = "cmi-m01-ec01-t1-gw01"
$avnsLocalSubnet = "10.50.0.0"
$avnsLocalSubnetMask = "255.255.255.0"

$avnsXRegGw = "10.60.0.1"
$avnsXRegMtu = "8000"
$avnsXRegName = "xregion-seg01"
$avnsXRegRegionType = "X_REGION"
$avnsXRegRouterName = "cmi-m01-ec01-t1-gw01"
$avnsXRegSubnet = "10.60.0.0"
$avnsXRegSubnetMask = "255.255.255.0"
$edgeClusterId = Get-VCFEdgeCluster | Select-Object -ExpandProperty id


# ==================== Download and Depoloy vRealize Lifecycle Manager ====================

# Create variable which identifies the vRealize Suite Lifecycle Manager Bundle
$vrslcmBundle = Get-VCFBundle | Where-Object { $_.description -Match "vRealize Suite Lifecycle Manager" }

# Download the vRealize Suite Lifecycle Manager Bundle and monitor the task until comleted
$requestBundle = Request-VCFBundle -id $vrslcmBundle.id

Start-Sleep 5

do { $taskStatus = Get-VCFTask -id $($requestBundle.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
logger "vRealize Suite Lifecycle Manager Download Complete"

# Create the JOSN Specification for vRealize Suite Lifecyclec Manager Deployment
logger "Creating JSON Specification File"
$vrslcmDepSpec = [PSCustomObject]@{apiPassword = 'VMware123!'; fqdn = 'xint-vrslcm01.elasticsky.org'; nsxtStandaloneTier1Ip = '10.60.0.250'; sshPassword = 'VMware123!' }
$vrslcmDepSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\vrslcmDepSpec.json

# Validate the settings
logger "Validating JSON Settings"
$vrslcmValidate = New-VCFvRSLCM -json $jsonPathDir\vrslcmDepSpec.json -validate
Start-Sleep 5
do { $taskStatus = Get-VCFTask -id $($vrslcmValidate.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
logger "Validation Complete"

# Deploy vRealize Suite Lifecycle Manager
$vrslcmDeploy = New-VCFvRSLCM -json $jsonPathDir\vrslcmDepSpec.json
logger "Deploying vRealize Suite Lifecycle Manager"
Start-Sleep 5
do { $taskStatus = Get-VCFTask -id $($vrslcmDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
logger "Deployment Completed Successfully"

# ==================== Create and deploy Certificate for vRSLCM ====================

$vrslcm = Get-VCFvRSLCM
$vrslcm | Add-Member -Type NoteProperty -Name Type -Value "VRSLCM"

# Create JSON Specification for vRSLCM Certificate Signing Request
logger "Creating JSON Specification for vRSLCM Certificate Signing Request"
$csrVrslcm = [PSCustomObject]@{
    csrGenerationSpec = @{country = 'us'; email = 'admin@elasticsky.org'; keyAlgorithm = 'RSA'; keySize = '2048'; locality = 'Champaign'; organization = 'Elasticsky'; organizationUnit = 'IT'; state = 'Illinois' }
    resources         = @(@{fqdn = $vrslcm.fqdn; name = $vrslcm.fqdn; sans = @($vrslcm.fqdn); resourceID = $vrslcm.id; type = $vrslcm.Type })
}

# Create the JSON file for vRSLCM CSR Generation
$csrVrslcm | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\csrsvrslcmSpec.json

# Generate CSR for vRSLCM Certificate
logger "Requesting vRSLCM CSR for $domainName"
$csrVrslcmReq = Request-VCFCertificateCSR -domainName $domainName -json $jsonPathDir\csrsvrslcmSpec.json
do { $taskStatus = Get-VCFTask -id $($csrVrslcmReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

# Create JSON Specification for vRSLCM Certificate Generation
logger "Creating JSON specification for vRSLCM Certificate Request"
$certVrslcmSpec = [PSCustomObject]@{
    caType    = "Microsoft"
    resources = @(@{fqdn = $vrslcm.fqdn; name = $vrslcm.fqdn; sans = @($vrslcm.fqdn); resourceID = $vrslcm.id; type = $vrslcm.type })
}

# Request the creation of certificate for vRSLCM
$certvrslcmSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certVrslcmSpec.json

logger "Generating vRSLCM Certificate on CA for $domainName"
$certVrslcmCreateReq = Request-VCFCertificate -domainName $domainName -json $jsonPathDir\certVrslcmSpec.json
do { $taskStatus = Get-VCFTask -id $($certVrslcmCreateReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

# Install certificate on vRSLCM
$certVrslcmInstallSpec = [PSCustomObject]@{
    operationType = "INSTALL"
    resources     = @(@{fqdn = $vrslcm.fqdn; name = $vrslcm.fqdn; sans = @($vrslcm.fqdn); resourceID = $vrslcm.id; type = $vrslcm.type })
}

$certVrslcmInstallSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certVrslcmInstallSpec.json
logger "Installing Certificates for $domainName"
$certVrslcmInstallReq = Set-VCFCertificate -domainName $domainName -json $jsonPathDir\certVrslcmInstallSpec.json
do { $taskStatus = Get-VCFTask -id $($certVrslcmInstallReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
logger "vRSLCM Certificate successfully installed"

# ====================================================================================
#                       Deploy vRealize Suite Lifecycle Manager                 
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

logger "Connect to Software Depot, download and deploy vRealize Suite Lifecycle Manager, replace default certificate"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager variables
$sddcManagerfqdn = "cmi-vcf01.elasticsky.org"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!"
$sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!"
$vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters

# Authenticate to SDDC Manager using global variables defined at the top of the script
Request-VCFToken -fqdn $sddcManagerfqdn -username $ssoUser -password $ssoPass
Connect-VIServer -server $vcenter.fqdn -user $ssoUser -password $ssoPass

Start-Sleep 5


# ==================== Configure Repository ====================

# Variables for configuring the SDDC Manager Depot
$depotUser = "nasawest@vmware.com"
$depotPassword = "Supporthelp1$"

# NOTE:  The changes to the base images and poll interval are for demonstration purposes, and should only be changed after you have consulted with your customer regarding upgrades to any existing VCF deployments
logger "Creating Script to Modify Default LCM Settings for Base Bundle and Polling Interval"
$lcmChangeScript += "sed -i 's/lcm.core.manifest.poll.interval=300000/lcm.core.manifest.poll.interval=120000/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vrslcm.install.base.version=8.1.0-16776528/vrslcm.install.base.version=8.6.2-19221620/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vra.install.base.version=8.1.0-15986821/vra.install.base.version=8.6.0-00000000/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vrops.install.base.version=8.1.1-16522874/vrops.install.base.version=8.6.0-00000000/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "sed -i 's/vrli.install.base.version=8.1.1-16281169/vrli.install.base.version=8.6.0-00000000/g' /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "echo wsa.install.base.version=3.3.6-00000000 >> /opt/vmware/vcf/lcm/lcm-app/conf/application-prod.properties`n"
$lcmChangeScript += "systemctl restart lcm`n"
$lcmChangeScript += "systemctl status lcm | grep Active`n"
logger "Writing Changes to SDDC Manager Lifecycle Manager and Restarting LCM Service"
Invoke-VMScript -ScriptType bash -GuestUser $sddcUser -GuestPassword $sddcPassword -VM $sddcMgrVMName -ScriptText $lcmChangeScript

Start-Sleep 60

# Set Depot credentials in SDDC Manager
logger "Set the Bundle Depot Credentials in SDDC Manager"
Set-VCFDepotCredential -username $depotUser -password $depotPassword

Start-Sleep 600

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

Start-Sleep 30

# ==================== Create and deploy Certificate for vRSLCM ====================


$domainName = Get-VCFWorkloadDomain | Where-Object {$_.type -match "MANAGEMENT"} | Select-Object -ExpandProperty name
$vrslcm = Get-VCFvRSLCM
$vrslcm | Add-Member -Type NoteProperty -Name Type -Value "VRSLCM"

# Create JSON Specification for vRSLCM Certificate Signing Request
logger "Creating JSON Specification for vRSLCM Certificate Signing Request"
$csrVrslcm = [PSCustomObject]@{
    csrGenerationSpec = @{country = 'us';email= 'admin@elasticsky.org';keyAlgorithm= 'RSA';keySize= '2048';locality = 'Champaign';organization= 'Elasticsky';organizationUnit = 'IT';state= 'Illinois'}
    resources         = @(@{fqdn= $vrslcm.fqdn;name= $vrslcm.fqdn;sans= @($vrslcm.fqdn);resourceID= $vrslcm.id;type= $vrslcm.Type})
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
$certVrslcmSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certVrslcmSpec.json

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

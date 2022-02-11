############################################################################
#              Configure vRSLCM for WSA Cluster Deployment                 #
#                                                                          #
#    Words and Music By,  Alasdair Carnie, Ben Sier and Henk Engelsman     #
#               Backing Band - Gary Blake and the VVS Team                 #
#                                                                          #
############################################################################

Import-Module -Name VMware.PowerCLI
Import-Module -Name PowerValidatedSolutions
Import-Module -Name PowerVCF

# SDDC Manager Varialbles
$sddcManagerFqdn = "cmi-vcf01.elasticsky.org"
$sddcManagerUser = "administrator@vsphere.local"
$sddcManagerPass = "VMware123!"

# vRSLCM and WSA Deploy Variables
$wSaCertificateAlias = "xint-wsa01"
$wSaCertChainPath = "C:\VLC-New\CertGenVVS\SignedByMSCACerts\xint-wsa01\xint-wsa01.2.chain.pem"

$globalPasswordAlias = "global-env-admin"
$globalPassword = "VMware123!"
$globalUserName = "admin"

$wSaAdminPasswordAlias = "xint-wsa-admin"
$wSaAdminPassword = "VMware123!"
$wSaAdminUserName = "admin"

$wSaConfigAdminPasswordAlias = "xint-wsa-configadmin"
$wSaConfigAdminPassword = "VMware123!"
$wSaConfigAdminUserName = "configadmin"

$vCenterName = "cmi-m01-vc01"
$vCenterHost = "cmi-m01-vc01.elasticsky.org"
$vCenterUsername = "administrator@vsphere.local"
$vCenterPassword = "VMware123!"

$vrslcmVmname = "xint-vrslcm01"
$domain = "elasticsky.org"
$vrslcmHostname = $vrslcmVmname + "." + $domain
$vrslcmUsername = "vcfadmin@local"
$vrlscmPassword = "VMware123!"
$vrslcmDefaultAccount = "admin" 
$vrslcmAdminEmail = $vrslcmDefaultAccount + "@" + $domain 
$vrslcmDcName = "xint-m01-dc01"
$vrslcmDcLocation = "Champaign, Illinois, US"


$dns1 = "10.0.0.201"
$ntp1 = "10.0.0.201"
$gateway = "10.60.0.1"
$netmask = "255.255.255.0"

$deployDatastore = "cmi-m01-cl01-ds-vsan01"
$deployCluster = "cmi-m01-dc01#cmi-m01-cl01"
$deployNetwork = "xregion-seg01"
$deployVmFolderName = "cmi-m01-fd-mgmt"

$vidmVmName = "xint-wsa01a"
$vidmHostname = $vidmVMName + "." + $domain
$vidmIp = "10.60.0.31"
$vidmVersion = "3.3.5"
$certificateAlias = "xint-wsa01"
$sddcDomainName = "cmi-m01"

$antiAffinityRuleName = "xint-anti-affinity-rule-wsa"
$antiAffinityVMs = "xint-wsa01a"
$drsGroupName = "xint-vm-group-wsa"

$wsaFqdn = "xint-wsa01a.elasticsky.org"
$wsaAdminPassword = "VMware123!"
$wsaRootPassword = "VMware123!"

$domainFqdn = "elasticsky.org"
$baseDnUsers = "OU=Security Users,DC=elasticsky,DC=org"
$baseDnGroups = "OU=Security Groups,DC=elasticsky,DC=org"
$wsaBindUserDn = "CN=svc-wsa-ad,OU=Security Users,DC=elasticsky,DC=org"
$wsaBindUserPassword = "VMware123!"

$adGroups = "gg-vrslcm-admins","gg-vrslcm-release-managers","gg-vrslcm-content-developers","gg-wsa-admins","gg-wsa-directory-admins","gg-wsa-read-only"

$rootCaPath = "C:\VLC-New\CertGenVVS\SignedByMSCACerts\RootCA\Root64.cer"

$minLen = "6"
$minLower = "1"
$minUpper = "1"
$minDigit = "1"
$minSpecial = "1"
$history = "5"
$maxConsecutiveIdenticalCharacters = "1"
$maxPreviousPasswordCharactersReused = "0"
$tempPasswordTtlInHrs = "24"
$passwordTtlInDays = "90" 
$notificationThresholdInDays = "15" 
$notificationIntervalInDays = "1"

$numAttempts = "5"
$attemptInterval = "15"
$unlockInterval = "15"

$wsaSuperAdminGroup = "gg-wsa-admins"
$wsaDirAdminGroup = "gg-wsa-directory-admins"
$wsaReadOnlyGroup = "gg-wsa-read-only"

# Import WSA Certificate into vRSLCM
Import-vRSLCMLockerCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -certificateAlias $wSaCertificateAlias -certChainPath $wSaCertChainPath

# Create Locker Passwords for WSA
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $wSaAdminPasswordAlias -password $wSaAdminPassword -userName $wSaAdminUserName
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $wSaConfigAdminPasswordAlias -password $wSaConfigAdminPassword -userName $wSaConfigAdminUserName

# Create Locker Password for global environment admin
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $globalPasswordAlias -password $globalPassword -userName $globalUserName


# Log into vRSLCM to create headers and variables for use with API.  This also create the global variable $vrslcmHeaders
Request-vRSLCMToken -fqdn $vrslcmHostname -username $vrslcmUsername -password $vrlscmPassword

$vc_vmid = $(Get-vRSLCMLockerPassword | where {$_.alias -match "svc-vrslcm-vsphere-cmi_m01_vc01"}).vmid
$vc_alias = $(Get-vRSLCMLockerPassword | where {$_.alias -match "svc-vrslcm-vsphere-cmi_m01_vc01"}).alias
$vc_username = $(Get-vRSLCMLockerPassword | where {$_.alias -match "svc-vrslcm-vsphere-cmi_m01_vc01"}).username
$vcPassword="locker`:password`:$vc_vmid`:$vc_alias" #note the escape character


# Create Cross Region Datacenter in vRSLCM
$dcuri = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters"
$data =@{
    dataCenterName="$vrslcmDcName"
    primaryLocation="$vrslcmDcLocation"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Method Post -Uri $dcuri -Headers $vrslcmHeaders -Body $data 
    $response
} catch {
    write-host "Failed to create datacenter $data.dataCenterName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$datacenterRequestId = $response.requestId
$dc_vmid = $response.dataCenterVmid

# Create and Register vCenter in the newly created datacenter in vRSLCM
$data=@{
    vCenterHost="$vCenterHost"
    vCenterName="$vCenterName"
    vcPassword="locker`:password`:$vc_vmid`:$vc_alias" #note the escape characters
    vcUsedAs="MANAGEMENT"
    vcUsername="$vc_username"
  } | ConvertTo-Json
$urivCenters = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters/$dc_vmid/vcenters"

try {
    $response = Invoke-RestMethod -Method Post -Uri $urivCenters -Headers $vrslcmHeaders -Body $data 
} catch {
    write-host "Failed to add vCenter $data.vCenterHost" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

# Create the variables needed as part of the JSON to deploy the Global Environment and WSA
$vc_vmid = $(Get-vRSLCMLockerPassword | where {$_.alias -match "svc-vrslcm-vsphere-cmi_m01_vc01"}).vmid
$ge_vmid = $(Get-vRSLCMLockerPassword | where {$_.alias -match "global-env-admin"}).vmid
$wsaAdmin_vmid = $(Get-vRSLCMLockerPassword | where {$_.alias -match "xint-wsa-admin"}).vmid
$wsaConfigAdmin_vmid = $(Get-vRSLCMLockerPassword | where {$_.alias -match "xint-wsa-configadmin"}).vmid

$vc_alias = $(Get-vRSLCMLockerPassword | where {$_.alias -match "svc-vrslcm-vsphere-cmi_m01_vc01"}).alias
$ge_alias = $(Get-vRSLCMLockerPassword | where {$_.alias -match "global-env-admin"}).alias
$wsaAdmin_alias = $(Get-vRSLCMLockerPassword | where {$_.alias -match "xint-wsa-admin"}).alias
$wsaConfigAdmin_alias = $(Get-vRSLCMLockerPassword | where {$_.alias -match "xint-wsa-configadmin"}).alias

$vc_username = $(Get-vRSLCMLockerPassword | where {$_.alias -match "svc-vrslcm-vsphere-cmi_m01_vc01"}).username
$ge_username = $(Get-vRSLCMLockerPassword | where {$_.alias -match "global-env-admin"}).username
$wsaAdmin_username = $(Get-vRSLCMLockerPassword | where {$_.alias -match "xint-wsa-admin"}).username
$wsaConfigAdmin_username = $(Get-vRSLCMLockerPassword | where {$_.alias -match "xint-wsa-configadmin"}).username

$vcPasswordLockerEntry="locker`:password`:$vc_vmid`:$vc_alias"
$globalPasswordLockerEntry="locker`:password`:$ge_vmid`:$ge_alias"
$wsaAdminPasswordLockerEntry="locker`:password`:$wsaAdmin_vmid`:$wsaAdmin_alias"
$wsaConfigAdminPasswordLockerEntry="locker`:password`:$wsaConfigAdmin_vmid`:$wsaConfigAdmin_alias"

$certificateId = $(Get-vRSLCMLockerCertificate | where {$_.alias -match "$certificateAlias"}).vmid
$CertificateLockerEntry="locker`:certificate`:$certificateId`:$CertificateAlias"

# Create the JSON for Global Environment and WSA Deployment
$uri = "https://$vrslcmHostname/lcm/lcops/api/v2/environments"
$vidmDeployJSON=@"
{
    "environmentName": "globalenvironment",
    "infrastructure": {
      "properties": {
        "dataCenterVmid": "$dc_vmId",
        "regionName": "",
        "zoneName": "",
        "vCenterName": "$vCenterName",
        "vCenterHost": "$vCenterHost",
        "vcUsername": "$vc_username",
        "vcPassword": "$vcPasswordLockerEntry",
        "acceptEULA": "true",
        "enableTelemetry": "true",
        "defaultPassword": "$globalPasswordLockerEntry",
        "certificate": "$CertificateLockerEntry",
        "cluster": "$deployCluster",
        "storage": "",
        "folderName": "",
        "resourcePool": "",
        "diskMode": "thin",
        "network": "$deployNetwork",
        "masterVidmEnabled": "false",
        "dns": "$dns1",
        "domain": "$domain",
        "gateway": "$gateway",
        "netmask": "$netmask",
        "searchpath": "$domain",
        "timeSyncMode": "ntp",
        "ntp": "",
        "isDhcp": "false",
        "vcfProperties": "{\"vcfEnabled\":true,\"sddcManagerDetails\":[{\"sddcManagerHostName\":\"cmi-vcf01.elasticsky.org\",\"sddcManagerName\":\"default\",\"sddcManagerVmid\":\"default\"}]}",
        "_selectedProducts": "[{\"id\":\"vidm\",\"type\":\"new\",\"selected\":true,\"sizes\":{\"3.3.5\":[\"standard\",\"cluster\"]},\"selectedVersion\":\"3.3.5\",\"selectedDeploymentType\":\"standard\",\"tenantId\":\"Standalone vRASSC\",\"description\":\"VMware Identity Manager\",\"detailsHref\":\"https://docs.vmware.com/en/VMware-Identity-Manager/index.html\",\"errorMessage\":null,\"productVersions\":[{\"version\":\"3.3.5\",\"deploymentType\":[\"standard\",\"cluster\"],\"productDeploymentMetaData\":{\"sizingURL\":null,\"productInfo\":\"VMware Identity Manager - 3.3.5\",\"deploymentType\":[\"Standard\",\"Cluster\"],\"deploymentItems\":{\"Node Count\":[\"1\",\"3\"]},\"additionalInfo\":[\"*Standard - One vIDM node will be deployed\",\"*Cluster - Three vIDM node will be deployed\"]}}]}]",
        "_isRedeploy": "false",
        "_isResume": "false",
        "_leverageProximity": "false",
        "__isInstallerRequest": "false"
      }
    },
    "products": [
      {
        "id": "vidm",
        "version": "$vidmVersion",
        "properties": {
          "vidmAdminPassword": "$wsaAdminPasswordLockerEntry",
          "syncGroupMembers": true,
          "nodeSize": "medium",
          "defaultConfigurationUsername": "$wsaConfigAdmin_username",
          "defaultConfigurationEmail": "$vrslcmAdminEmail",
          "defaultConfigurationPassword": "$wsaConfigAdminPasswordLockerEntry",
          "defaultTenantAlias": "",
          "vidmDomainName": "",
          "certificate": "$CertificateLockerEntry",
          "contentLibraryItemId": "",
          "fipsMode": "false"
        },
        "clusterVIP": {
          "clusterVips": []
        },
        "nodes": [
          {
            "type": "vidm-primary",
            "properties": {
                "vmName": "xint-wsa01a",
                "hostName": "xint-wsa01a.elasticsky.org",
                "ip": "10.60.0.31",
                "storage": "$deployDatastore"
            }
          }
        ]
      }
    ]
  }
"@

# Deploy Global Environment and WSA
try {
     $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $vrslcmHeaders -Body $vidmDeployJSON
 } catch {
     write-host "Failed to create Global Environment" -ForegroundColor red
     Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
     Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
     break
 }
$vidmRequestId = $response.requestId


# Check VIDM Deployment Request
$uri = "https://$vrslcmHostname/lcm/request/api/v2/requests/$vidmRequestId"
Write-Host "VIDM Deployment Started at" (get-date -format HH:mm)
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $vrslcmHeaders
$Timeout = 3600
$timer = [Diagnostics.Stopwatch]::StartNew()
while (($timer.Elapsed.TotalSeconds -lt $Timeout) -and (-not ($response.state -eq "COMPLETED"))) {
    Start-Sleep -Seconds 60
    Write-Host "VIDM Deployment Status at " (get-date -format HH:mm) $response.state
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $vrslcmHeaders
    if ($response.state -eq "FAILED"){
        Write-Host "FAILED to Deploy VIDM " (get-date -format HH:mm) -ForegroundColor White -BackgroundColor Red
        Break
    }
}
$timer.Stop()
Write-Host "VIDM Deployment Status at " (get-date -format HH:mm) $response.state -ForegroundColor Black -BackgroundColor Green

#========  Post WSA Deployment =========

# Set Anti-Affinity Rules
Add-AntiAffinityRule -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -ruleName $antiAffinityRuleName -antiAffinityVMs $antiAffinityVMs
Add-ClusterGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -drsGroupName $drsGroupName -drsGroupVMs $antiAffinityVMs

Sleep 5

# Configure NTP on the Clustered Workspace ONE Access Instance
Set-WorkspaceOneNtpConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaFqdn $wsaFqdn -rootPass $wsaRootPassword

Sleep 5

# Configure Identity Source for the Clustered Workspace ONE Access Instance
Add-WorkspaceOneDirectory -server $wsaFqdn -user admin -pass $wsaAdminPassword -domain $domainFqdn -baseDnUser $baseDnUsers -baseDnGroup $baseDnGroups -bindUserDn $wsaBindUserDn -bindUserPass $wsaBindUserPassword -adGroups $adGroups -certificate $rootCaPath -protocol ldaps

Sleep 5

# Add Security Roles to WSA
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaSuperAdminGroup -role "Super Admin"
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaDirAdminGroup -role "Directory Admin"
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaReadOnlyGroup -role "ReadOnly Admin"

Sleep 5

# Set WSA Password Policy
Request-WSAToken -fqdn $wsaFqdn -user admin -pass $wsaAdminPassword
Set-WSAPasswordPolicy -minLen $minLen -minLower $minLower -minUpper $minUpper -minDigit $minDigit -minSpecial $minSpecial -history $history -maxConsecutiveIdenticalCharacters $maxConsecutiveIdenticalCharacters -maxPreviousPasswordCharactersReused $maxPreviousPasswordCharactersReused -tempPasswordTtlInHrs $tempPasswordTtlInHrs -passwordTtlInDays $passwordTtlInDays -notificationThresholdInDays $notificationThresholdInDays -notificationIntervalInDays $notificationIntervalInDays | Get-WSAPasswordPolicy
Set-WSAPasswordLockout -numAttempts $numAttempts -attemptInterval $attemptInterval -unlockInterval $unlockInterval
############################################################################
#              Prepare vRSLCM for vRealize Suite Deployment                #
#                                                                          #
#    Words and Music By,  Alasdair Carnie, Ben Sier and Henk Engelsman     #
#               Backing Band - Gary Blake and the VVS Team                 #
#                                                                          #
############################################################################

# SDDC Manager Varialbles
$sddcManagerFqdn = "cmi-vcf01.elasticsky.org"
$sddcManagerUser = "administrator@vsphere.local"
$sddcManagerPass = "VMware123!"

# vCenter Variables
$vCenterName = "cmi-m01-vc01"
$vCenterHost = "cmi-m01-vc01.elasticsky.org"
$vCenterUsername = "administrator@vsphere.local"
$vCenterPassword = "VMware123!"

# vRSLCM Variables
$vrslcmVmname = "xint-vrslcm01"
$domain = "elasticsky.org"
$vrslcmHostname = $vrslcmVmname + "." + $domain
$vrslcmUsername = "vcfadmin@local"
$vrlscmPassword = "VMware123!"
# $vrslcmDefaultAccount = "admin" 
# $vrslcmAdminEmail = $vrslcmDefaultAccount + "@" + $domain 
$vrslcmDcName = "xint-m01-dc01"
$vrslcmDcLocation = "Champaign, Illinois, US"

# My VMware Account Variables
$MyVmwAlias = "MyVMware"
$MyVmwPassword = "Supporthelp1$"
$MyVmwUserName = "nasawest@vmware.com"

# WorkspaceONE Access Certificate and Locker Variables
$wSaCertificateAlias = "xint-wsa01"
$wSaCertChainPath = "c:\vlc\CertGenVVS\SignedByMSCACerts\xint-wsa01\xint-wsa01.2.chain.pem"
$globalPasswordAlias = "global-env-admin"
$globalPassword = "VMware123!"
$globalUserName = "admin"
$wSaAdminPasswordAlias = "xint-wsa-admin"
$wSaAdminPassword = "VMware123!"
$wSaAdminUserName = "admin"
$wSaConfigAdminPasswordAlias = "xint-wsa-configadmin"
$wSaConfigAdminPassword = "VMware123!"
$wSaConfigAdminUserName = "configadmin"

# vRealize Automation Locker Variables
$vRACertificateAlias = "xint-vra01"
$vRACertChainPath = "c:\vlc\CertGenVVS\SignedByMSCACerts\xint-vra01\xint-vra01.2.chain.pem"
$xintEnvPasswordAlias = "xint-env-admin"
$xintEnvPassword = "VMware123!"
$xintEnvUserName = "admin"
$vRARootPasswordAlias = "vra-root"
$vRARootPassword = "VMware123!"
$vRARootUserName = "root"

# vRealize Suite Product Version
$wsaVersion = "3.3.6"
$vraVersion = "8.6.2"
$vropsVersion = "8.6.2"
$vrliVersion = "8.6.2"

# Create Locker Password for My VMware Account
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $MyVmwAlias -password $MyVmwPassword -userName $MyVmwUserName

# Create Locker Password for global and xint environment admins
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $globalPasswordAlias -password $globalPassword -userName $globalUserName
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $xintEnvPasswordAlias -password $xintEnvPassword -userName $xintEnvUserName

# Create WorkspaceONE Access Locker Passwords
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $wSaAdminPasswordAlias -password $wSaAdminPassword -userName $wSaAdminUserName
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $wSaConfigAdminPasswordAlias -password $wSaConfigAdminPassword -userName $wSaConfigAdminUserName

# Create vRealize Automation Locker Account
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $vRARootPasswordAlias -password $vRARootPassword -userName $vRARootUserName

# Import WorkspaceOne Access Certificate into vRSLCM
Import-vRSLCMLockerCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -certificateAlias $wSaCertificateAlias -certChainPath $wSaCertChainPath

# Import vRealize Automation Certificate into vRSLCM
Import-vRSLCMLockerCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -certificateAlias $vRACertificateAlias -certChainPath $vRACertChainPath

# Log into vRSLCM to create headers and authentication variables for use with API.  This also create the global variable $vrslcmHeaders
Request-vRSLCMToken -fqdn $vrslcmHostname -username $vrslcmUsername -password $vrlscmPassword

# Get My VMware Locker Password information from Locker
$MyVmw_Id = $(Get-vRSLCMLockerPassword | where {$_.alias -match "MyVMware"}).vmid
$MyVmw_Alias = $(Get-vRSLCMLockerPassword | where {$_.alias -match "MyVMware"}).Alias
$MyVmw_username = $(Get-vRSLCMLockerPassword | where {$_.alias -match "MyVmware"}).username

# Create JSON file with MY VMware Settings
$MyVmwData=@{
  password = "locker`:password`:$MyVmw_Id`:$MyVmw_Alias" # Note the escape character
  userName = "$MyVmw_username"
  } | ConvertTo-Json

# Set URI for My VMware Account Creation
$urivRSLCMAccounts = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/my-vmware/accounts"

# Create the My VMware Account by Invoking the API
try {
    $response = Invoke-RestMethod -Method Post -Uri $urivRSLCMAccounts -Headers $vrslcmHeaders -Body $MyVmwData 
} catch {
    write-host "Failed to add My VMware Account $MyVmwData.vCenterHost" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

# Get Default vRSLCM to vCenter Integration Account Information from Locker
$vc_vmid = $(Get-vRSLCMLockerPassword | where {$_.alias -match "cmi-m01-vc01-cmi-m01-dc01"}).vmid
$vc_alias = $(Get-vRSLCMLockerPassword | where {$_.alias -match "cmi-m01-vc01-cmi-m01-dc01"}).alias
$vc_username = $(Get-vRSLCMLockerPassword | where {$_.alias -match "cmi-m01-vc01-cmi-m01-dc01"}).username
$vcPassword="locker`:password`:$vc_vmid`:$vc_alias" #note the escape character

# Create JSON configuration file for Datacenter Creation
$dcCreate =@{
    dataCenterName="$vrslcmDcName"
    primaryLocation="$vrslcmDcLocation"
} | ConvertTo-Json

# Set URI for vRSLCM Datacenter Creation
$dcuri = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters"

# Create Cross Region Datacenter in vRSLCM
try {
    $response = Invoke-RestMethod -Method Post -Uri $dcuri -Headers $vrslcmHeaders -Body $dcCreate 
    $response
} catch {
    write-host "Failed to create datacenter $dcCreate.dataCenterName" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}
$datacenterRequestId = $response.requestId
$dc_vmid = $response.dataCenterVmid


# Create JSON configuration file for add vCenter to newly created Datacenter
$vcAdd=@{
    vCenterHost="$vCenterHost"
    vCenterName="$vCenterName"
    vcPassword="locker`:password`:$vc_vmid`:$vc_alias" #note the escape characters
    vcUsedAs="MANAGEMENT"
    vcUsername="$vc_username"
  } | ConvertTo-Json

# Set URI for adding a vCenter to the newly created vRSLCM Datacenter
$urivCenters = "https://$vrslcmHostname/lcm/lcops/api/v2/datacenters/$dc_vmid/vcenters"

# Add vCenter to newly created Datacenter
try {
    $response = Invoke-RestMethod -Method Post -Uri $urivCenters -Headers $vrslcmHeaders -Body $vcAdd 
} catch {
    write-host "Failed to add vCenter $vcAdd.vCenterHost" -ForegroundColor red
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
    break
}

# Define a class for the vRS products array
class vrsBinInfo {
 [string]$productId
 [string]$productVersion
 [string]$productBinaryType
 [string]$productBinaryPath
 [string]$componentName
 [string]$mappingType 
 [string]$productName
 [string]$vidmRequestId
 [string]$removeBinary
}

# Create the vRS products array file and convert to JSON
#$vrsProducts = (Convertto-json @(
#[vrsBinInfo]@{productId="vrops";productVersion=$vropsVersion;productBinaryType="Install";productName="vRealize Operations"}
#))+(Convertto-json @([vrsBinInfo]@{productId="vrli";productVersion=$vrliVersion;productBinaryType="Install";productName="vRealize LogInsight"}
#))

#$vrsProducts = (ConvertTo-Json @(
#[vrsBinInfo]@{productId="vidm";productVersion=$wsaVersion;productBinaryType="Install";productName="VMware Identity Manager"}
#[vrsBinInfo]@{productId="vrops";productVersion=$vraVersion;productBinaryType="Install";productName="vRealize Operations"}
#[vrsBinInfo]@{productId="vra";productVersion=$vropsVersion;productBinaryType="Install";productName="vRealize Automation"}
#[vrsBinInfo]@{productId="vrli";productVersion=$vrliVersion;productBinaryType="Install";productName="vRealize Log Insight"}
#))


# Create the vRS products array file and convert to JSON
$vrsProducts = (Convertto-json @(
[vrsBinInfo]@{productId="vrops";productVersion=$vropsVersion;productBinaryType="Install";productName="vRealize Operations"}
))
$vrsProducts

# Set URI for vRealize Suite Binary downloads
$uriBinDl = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/my-vmware/product-binaries/download"

# Download the vRealize Suite Binaries by invoking the API
$vRSLCMBinDL = Invoke-RestMethod -Method Post -Uri $uriBinDl -Headers $vrslcmHeaders -Body $vrsProducts 
$resp = $vRSLCMBinDl.requestId
$urivRSLCMResp = "https://xint-vrslcm01.elasticsky.org/lcm/request/api/v2/requests/$resp"

do { $requestResponse = Invoke-RestMethod -Method Get -Uri $urivRSLCMResp -Headers $vrslcmHeaders;Start-Sleep 5} until ($requestResponse.Status -match "COMPLETED")

Start-Sleep 10



# Get All Available Product Binaries

Logger "Getting a list of all vRealize Products available for download"

$urivRSLCMBinList = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/my-vmware/product-binaries"
$BinList = Invoke-RestMethod -Method Get -Uri $urivRSLCMBinList -Headers $vrslcmHeaders

# Download WSA Installation Package

Logger "Downloading WorkspaceOne Access"

$GetWsa= @"
[
  {
  "productId":"vidm",
  "productVersion":"3.3.6",
  "productBinaryType":"Install",
  "productBinaryPath":null,
  "componentName":null,
  "mappingType":null,
  "productName":"VMware Identity Manager",
  "requestId":null,
  "removeBinary":null
  }
]
"@

$uriBinDl = "https://$vrslcmHostname/lcm/lcops/api/v2/settings/my-vmware/product-binaries/download"
$vRSLCMBinDL = Invoke-RestMethod -Method Post -Uri $uriBinDl -Headers $vrslcmHeaders -Body $GetWsa 
$resp = $vRSLCMBinDl.requestId

$urivRSLCMResp = "https://xint-vrslcm01.elasticsky.org/lcm/request/api/v2/requests/$resp"

do { $requestResponse = Invoke-RestMethod -Method Get -Uri $urivRSLCMResp -Headers $vrslcmHeaders;Start-Sleep 5} until ($requestResponse.Status -match "COMPLETED")

Start-Sleep 10

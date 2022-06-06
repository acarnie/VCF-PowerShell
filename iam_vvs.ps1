# Checking that the PowerShell Modules required for configurarion are installed
# At the top of the script, I have declared a set of variables as global.  The values contained in these variables are used by a variety of PowerShell cmdlets in this script, so declaring them for each cmdlet would be redundant.
# By declaring them as global, I can use their values anywhere in the script, including any custom functions I might create later.  I have also added a five second sleep between each set of cmdlets in order to give SDDC Manager / vCenter / WSA
# a chance to "settle" before running the next cmdlet.

# Global Variables
$global:sddcManagerFqdn = "cmi-vcf01.elasticsky.org"
$global:sddcManagerUser = "administrator@vsphere.local"
$global:sddcManagerPass = "VMware123!"
$global:domainFqdn = "elasticsky.org"
$global:wsaFqdn = "cmi-wsa01.elasticsky.org"
$global:sddcDomainName = "cmi-m01"
$global:domainBindUser = "svc-vsphere-ad"
$global:domainBindPass = "VMware123!"


# Add Active Directory as Identity Provider to vCenter
$domainControllerMachineName = "es-dc-01"
$baseGroupDn = "OU=Security Groups,dc=elasticsky,dc=org"
$baseUserDn = "OU=Security Users,dc=elasticsky,dc=org"

# This is an extra variable I created to point at the location of the Root CA Certificate.  It is used when adding AD to vCenter.
$certPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\RootCA\Root64.cer"

Add-IdentitySource -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -certificate $certPath -dcMachineName $domainControllerMachineName -baseGroupDn $baseGroupDn -baseUserDn $baseUserDn -protocol ldaps

Sleep 5

# Assign vCenter roles to Active Directory Groups
$vcenterAdminGroup = "gg-vc-admins"
$vcenterReadOnlyGroup = "gg-vc-read-only"

Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcenterAdminGroup -role Admin -propagate true -type group
Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcenterReadOnlyGroup -role ReadOnly -propagate true -type group

Sleep 5

# Assign vCenter Signle Sign-On Roles to Active Directory
$adGroup = "gg-sso-admins"

Add-SsoPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomainName -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $adGroup -ssoGroup "Administrators" -type group -source external

Sleep 5

# Configure the vCenter Server Appliance Password Expiration Date
$emailNotification = "administrator@elasticsky.org"
$maxDays = "180"

Set-vCenterPasswordExpiration -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -passwordExpires $true -email $emailNotification -maxDaysBetweenPasswordChange $maxDays

Sleep 5

# Configure the vCenter Single Sign-On Password and Lockout Policy
$ssoServerFqdn = "cmi-m01-vc01.elasticsky.org"
$ssoServerUser = "administrator@vsphere.local"
$ssoServerPass = "VMware123!"
$passwordCount = "5"
$minLength = "8"
$maxLength = "20"
$minNumericCount = "1"
$minSpecialCharCount = "1"
$maxIdenticalAdjacentCharacters = "3"
$minAlphabeticCount = "2"
$minUppercaseCount = "1"
$minLowercaseCount = "1"
$passwordLifetimeDays = "90"

$autoUnlockIntervalSec = "300"
$failedAttemptIntervalSec = "180"
$maxFailedAttempts = "5"


Connect-SsoAdminServer -Server $ssoServerFqdn -User $ssoServerUser -Password $ssoServerPass
Get-SsoPasswordPolicy | Set-SsoPasswordPolicy -ProhibitedPreviousPasswordsCount $passwordCount -MinLength $minLength -MaxLength $maxLength -MinNumericCount $minNumericCount -MinSpecialCharCount $minSpecialCharCount -MaxIdenticalAdjacentCharacters $maxIdenticalAdjacentCharacters -MinAlphabeticCount $minAlphabeticCount -MinUppercaseCount $minUppercaseCount -MinLowercaseCount $minLowercaseCount -PasswordLifetimeDays $passwordLifetimeDays

Sleep 5 

Get-SsoLockoutPolicy | Set-SsoLockoutPolicy -AutoUnlockIntervalSec $autoUnlockIntervalSec -FailedAttemptIntervalSec $failedAttemptIntervalSec -MaxFailedAttempts $maxFailedAttempts
Disconnect-SsoAdminServer -Server $ssoServerFqdn

Sleep 5

# Assign SDDC Manager Roles to Active Directory Groups
$vcfAdminGroup = "gg-vcf-admins"
$vcfOperatorGroup = "gg-vcf-operators"
$vcfViewerGroup = "gg-vcf-viewers"

Add-SddcManagerRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcfAdminGroup -role ADMIN -type group
Add-SddcManagerRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcfOperatorGroup -role OPERATOR -type group
Add-SddcManagerRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcfViewerGroup -role VIEWER -type group

Sleep 5

# Configure ESXi Hosts Password and Lockout Policies
$cluster = "cmi-m01-cl01"
$policy = "retry=5 min=disabled,disabled,disabled,disabled,15"

Set-EsxiPasswordPolicy -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -cluster $cluster -policy $policy

Sleep 5

#######  This completes the first part of the IAM Validated Solution.  Thr next section deal with deployment and configuration of the standalone Workspace ONE Access appliance #######

# Create Virtual Machine and Template Folder for the Standalone Workspace ONE Access Instance
$wsaFolder = "cmi-m01-fd-wsa"

Add-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -folderName $wsaFolder

Sleep 5

# Deploy the Standalone Workspace ONE Access Instance
$wsaIpAddress = "10.50.0.200"
$wsaGateway = "10.50.0.1"
$wsaSubnetMask = "255.255.255.0"

# This is an extra variable that points to the location of the WSA OVA file.
$wsaOvaPath = "E:\IDM\identity-manager-3.3.6.0-19203469_OVF10.ova"

# Deploy the WorkspaceOne Access Appliance
Install-WorkspaceOne -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaOvaPath $wsaOvaPath -wsaFqdn $wsaFqdn -wsaIpAddress $wsaIpAddress -wsaGateway $wsaGateway -wsaSubnetMask $wsaSubnetMask -wsaFolder $wsaFolder

Sleep 5

# Create a VM Group for the Standalone Workspace ONE Access Instance
$drsGroupName = "cmi-m01-vm-group-wsa"
$drsGroupVMs = "cmi-wsa01"

Add-ClusterGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -drsGroupName $drsGroupName -drsGroupVMs $drsGroupVMs

Sleep 5

# Complete the Initial Configuration of the Standalone Workspace ONE Access Instance
$wsaAdminPassword = "VMware123!"
$wsaRootPassword = "VMware123!"
$wsaSshUserPassword = "VMware123!"

Initialize-WorkspaceOne -wsaFqdn $wsaFqdn -adminPass $wsaAdminPassword -rootPass $wsaRootPassword -sshUserPass $wsaSshUserPassword

Sleep 5

# Configure NTP on the Standalone Workspace ONE Access Instance - NO ADDITONAL VARIABLES
Set-WorkspaceOneNtpConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaFqdn $wsaFqdn -rootPass $wsaRootPassword

Sleep 5

# Replace the Certificate of the Standalone Workspace ONE Access Instance
# These are additional variables to point at the location of the certificate files needed for replacing the self signed certificate on the WSA Appliance
$rootCaPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\RootCA\Root64.cer"
$wsaCertKeyPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\cmi-wsa01\cmi-wsa01.key"
$wsaCertPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\cmi-wsa01\cmi-wsa01.7.crt"

Install-WorkspaceOneCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaFqdn $wsaFqdn -rootPass $wsaRootPassword -sshUserPass $wsaSshUserPassword -rootCa $rootCaPath -wsaCertKey $wsaCertKeyPath -wsaCert $wsaCertPath

Sleep 5

# Configure SMTP on the Standalone Workspace ONE Access Instance
$smtpServerFqdn = "smtp.elasticsky.org"
$smtpServerPort = "25"
$smtpEmailAddress = "cmi-wsa@elasticsky.org"

Set-WorkspaceOneSmtpConfig -server $wsaFqdn -user admin -pass $wsaAdminPassword -smtpFqdn $smtpServerFqdn -smtpPort $smtpServerPort -smtpEmail $smtpEmailAddress

Sleep 5

# Configure Identity Source for the Standalone Workspace ONE Access Instance
$baseDnUsers = "OU=Security Users,dc=elasticsky,DC=org"
$baseDnGroups = "OU=Security Groups,dc=elasticsky,DC=org"
$wsaBindUserDn = "CN=svc-wsa-ad,OU=Security Users,dc=elasticsky,DC=org"
$wsaBindUserPassword = "VMware123!"
$adGroups = "gg-nsx-enterprise-admins","gg-nsx-network-admins","gg-nsx-auditors","gg-wsa-admins","gg-wsa-directory-admins","gg-wsa-read-only"

Add-WorkspaceOneDirectory -server $wsaFqdn -user admin -pass $wsaAdminPassword -domain $domainFqdn -baseDnUser $baseDnUsers -baseDnGroup $baseDnGroups -bindUserDn $wsaBindUserDn -bindUserPass $wsaBindUserPassword -adGroups $adGroups -certificate $rootCaPath -protocol ldaps

Sleep 5

# Configure Local Password Policy for the Standalone Workspace ONE Access Instance
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

# Configure Local Password Policy for the Standalone Workspace ONE Access Instance
Request-WSAToken -fqdn $wsaFqdn -user admin -pass $wsaAdminPassword
Set-WSAPasswordPolicy -minLen $minLen -minLower $minLower -minUpper $minUpper -minDigit $minDigit -minSpecial $minSpecial -history $history -maxConsecutiveIdenticalCharacters $maxConsecutiveIdenticalCharacters -maxPreviousPasswordCharactersReused $maxPreviousPasswordCharactersReused -tempPasswordTtlInHrs $tempPasswordTtlInHrs -passwordTtlInDays $passwordTtlInDays -notificationThresholdInDays $notificationThresholdInDays -notificationIntervalInDays $notificationIntervalInDays | Get-WSAPasswordPolicy
Set-WSAPasswordLockout -numAttempts $numAttempts -attemptInterval $attemptInterval -unlockInterval $unlockInterval

Sleep 5

# Assign Workspace ONE Access Roles to Active Directory Groups
$wsaSuperAdminGroup = "gg-wsa-admins"
$wsaDirAdminGroup = "gg-wsa-directory-admins"
$wsaReadOnlyGroup = "gg-wsa-read-only"

# Assign Workspace ONE Access Roles to Active Directory Groups
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaSuperAdminGroup -role "Super Admin"
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaDirAdminGroup -role "Directory Admin"
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaReadOnlyGroup -role "ReadOnly Admin"

Sleep 5

# The standalone Workspace ONE Access Appliance is now deployed and configured, ready for NSX-T Manager to be integrated for centralised identity management

# Integrate NSX-T Data Center with the Standalone Workspace ONE Access Instance
Set-WorkspaceOneNsxtIntegration -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -wsaFqdn $wsaFqdn -wsaUser admin -wsaPass $wsaAdminPassword

Sleep 5


# Assign NSX-T Data Center Roles to Active Directory Groups
$nsxEnterpriseAdminGroup = "gg-nsx-enterprise-admins@elasticsky.org"
$nsxNetworkEngineerGroup = "gg-nsx-network-admins@elasticsky.org"
$nsxAuditorGroup = "gg-nsx-auditors@elasticsky.org"

Add-NsxtVidmRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -type group -principal $nsxEnterpriseAdminGroup -role enterprise_admin
Add-NsxtVidmRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -type group -principal $nsxNetworkEngineerGroup -role network_engineer
Add-NsxtVidmRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -type group -principal $nsxAuditorGroup -role auditor
Sleep 5

# Configure the Authentication Policy for NSX Managers and NSX-T Edge Clusters
$apiLockoutPeriod = 900
$apiResetPeriod = 120
$apiMaxAttempt = 5
$cliLockoutPeriod = 900
$cliMaxAttempt = 5
$minPasswordLength = 15

Set-NsxtManagerAuthenticationPolicy -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -apiLockoutPeriod $apiLockoutPeriod -apiResetPeriod $apiResetPeriod -apiMaxAttempt $apiMaxAttempt -cliLockoutPeriod $cliLockoutPeriod -cliMaxAttempt $cliMaxAttempt -minPasswdLength $minPasswordLength

Sleep 5

# Configure the Authentication Policy for NSX Edge Nodes
$cliLockoutPeriod = 900
$cliMaxAttempt = 5
$minPasswdLength = 15

Set-NsxtEdgeNodeAuthenticationPolicy -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -cliLockoutPeriod $cliLockoutPeriod -cliMaxAttempt $cliMaxAttempt -minPasswdLength $minPasswdLength

Sleep 5

# Define a Custom Role in vSphere for the NSX-T Data Center Service Accounts
$vsphereRoleName = "NSX-T Data Center to vSphere Integration"

# This is an additional variable to point to the location of the custom role template
$roleTmplPath = "C:\Program Files\WindowsPowerShell\Modules\PowerValidatedSolutions\1.4.0\vSphereRoles\nsx-vsphere-integration.role"

Add-vSphereRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -roleName $vsphereRoleName -template $roleTmplPath

Sleep 5

# Add NSX-T Data Center Service Accounts to the vCenter Single Sign-On Built-In Identity Provider License Administrators Group
# NOTE:  I have changed the -domain variable was changed from $domainFqdn to $ssoLocal to avoid conflict with an earlier use of the variable
$serviceAccount = "svc-cmi-m01-nsx01-cmi-m01-vc01"
$ssoLocal = "vsphere.local"

Add-SsoPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomainName -domain $ssoLocal -principal $serviceAccount -ssoGroup "LicenseService.Administrators" -type user -source local

Sleep 5

# Reconfigure the vSphere Role and Permissions Scope for NSX-T Data Center Service Accounts
# NOTE. This reconfigures the MGMT WLD only.  If you have also cdeployed VI WLDs, you can uncomment and use the additional cmdlets below for each VI WLD.
$mgmtSddcDomainName = "cmi-m01"
$mgmtServiceAccount = "svc-cmi-m01-nsx01-cmi-m01-vc01"

Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain vsphere.local -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $mgmtServiceAccount -role $vsphereRoleName -propagate true -type user -localdomain
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain vsphere.local -workloadDomain $mgmtSddcDomainName  -principal $mgmtServiceAccount -role "NoAccess"

Sleep 5

# $wldSddcDomainName = "cmi-w01"
# $wldServiceAccount = "svc-sfo-w01-nsx01-sfo-w01-vc01"
# Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain vsphere.local -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $wldServiceAccount -role $vsphereRoleName -propagate true -type user -localdomain
# Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain vsphere.local -workloadDomain $wldSddcDomainName  -principal $mgmtServiceAccount -role "NoAccess"

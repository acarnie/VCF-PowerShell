# ================================================================================================================
#                            VMware Validated Design - Identity and Access Management - Part 1                
#                                                                                    
#  You must have PowerVCF, PowerCLI and Power Validated Solutions Modules installed in order to use this script     
#                                                                                    
#                                    Words and Music By The VVS Team and Alasdair Carnie                      
# ================================================================================================================

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

Logger "The Identity and Access Management VVS - Brought to you by the VVS Team, the letters L and F and by the number 42"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# Variables
$sddcManagerFqdn = "cmi-vcf01.elasticsky.org"
$sddcManagerUser = "administrator@vsphere.local"
$sddcManagerPass = "VMware123!"
$domainFqdn = "elasticsky.org"
$wsaFqdn = "cmi-wsa01.elasticsky.org"
$sddcDomainName = "cmi-m01"
$domainBindUser = "svc-vsphere-ad"
$domainBindPass = "VMware123!"

# Add Active Directory as Identity Provider to vCenter
logger "Integrating vCenter with Active Directory"
$domainControllerMachineName = "es-dc-01"
$baseGroupDn = "OU=Security Groups,dc=elasticsky,dc=org"
$baseUserDn = "OU=Security Users,dc=elasticsky,dc=org"

# This is an extra variable I created to point at the location of the Root CA Certificate.  It is used when adding AD to vCenter.
$certPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\RootCA\Root64.cer"

Add-IdentitySource -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -certificate $certPath -dcMachineName $domainControllerMachineName -baseGroupDn $baseGroupDn -baseUserDn $baseUserDn -protocol ldaps

Start-Sleep 5

# Assign vCenter roles to Active Directory Groups
logger "Assigning Active Directory global groups vCenter Administration and Read-Only roles"
$vcenterAdminGroup = "gg-vc-admins"
$vcenterReadOnlyGroup = "gg-vc-read-only"

Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcenterAdminGroup -role Admin -propagate true -type group
Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcenterReadOnlyGroup -role ReadOnly -propagate true -type group

Start-Sleep 5

# Assign vCenter Signle Sign-On Roles to Active Directory
logger"Assigning an Active Directory global group for SSO admin"
$adGroup = "gg-sso-admins"

Add-SsoPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomainName -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $adGroup -ssoGroup "Administrators" -type group -source external

Start-Sleep 5

# Configure the vCenter Server Appliance Password Expiration Date
logger "Setting the vCenter Appliance root password expiry period to 180 days"
$emailNotification = "administrator@elasticsky.org"
$maxDays = "180"

Set-vCenterPasswordExpiration -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -passwordExpires $true -email $emailNotification -maxDaysBetweenPasswordChange $maxDays

Start-Sleep 5

# Configure the vCenter Single Sign-On Password and Lockout Policy
logger "Setting the vCenter Single Sign-On password and lockout policies"
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
Disconnect-SsoAdminServer -Server $ssoServerFqdn

Sleep 5 

Get-SsoLockoutPolicy | Set-SsoLockoutPolicy -AutoUnlockIntervalSec $autoUnlockIntervalSec -FailedAttemptIntervalSec $failedAttemptIntervalSec -MaxFailedAttempts $maxFailedAttempts
Disconnect-SsoAdminServer -Server $ssoServerFqdn

Start-Sleep 5

# Assign SDDC Manager Roles to Active Directory Groups
logger "Assigning Active Directory global groups to SDDC Manager Roles for admin, operators and read-only"
$vcfAdminGroup = "gg-vcf-admins"
$vcfOperatorGroup = "gg-vcf-operators"
$vcfViewerGroup = "gg-vcf-viewers"

Add-SddcManagerRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcfAdminGroup -role ADMIN -type group
Add-SddcManagerRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcfOperatorGroup -role OPERATOR -type group
Add-SddcManagerRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vcfViewerGroup -role VIEWER -type group

Start-Sleep 5

# Configure ESXi Hosts Password and Lockout Policies
logger "Setting the ESXi Host password expiry policy"
$cluster = "cmi-m01-cl01"
$policy = "retry=5 min=disabled,disabled,disabled,disabled,15"

Set-EsxiPasswordPolicy -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -cluster $cluster -policy $policy

Start-Sleep 5

#######  This completes the first part of the IAM Validated Solution.  Thr next part deals with deployment and configuration of the standalone Workspace ONE Access appliance #######

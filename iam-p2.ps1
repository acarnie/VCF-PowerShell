# ================================================================================================================
#                            VMware Validated Design - Identity and Access Management - Part 2                
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

# Create a folder in Vcenter to hold the WSA Appliance
logger "Create a flder in VM's and Templates"
$wsaFolder = "cmi-m01-fd-wsa"
Add-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -folderName $wsaFolder

Start-Sleep 5

# Deploy the Standalone Workspace ONE Access Instance
logger "Deploying the standalone WSA Applance"
$wsaIpAddress = "10.50.0.200"
$wsaGateway = "10.50.0.1"
$wsaSubnetMask = "255.255.255.0"

# This is an extra variable that points to the location of the WSA OVA file.
$wsaOvaPath = "E:\IDM\identity-manager-3.3.6.0-19203469_OVF10.ova"

# Deploy the WorkspaceOne Access Appliance
Install-WorkspaceOne -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaOvaPath $wsaOvaPath -wsaFqdn $wsaFqdn -wsaIpAddress $wsaIpAddress -wsaGateway $wsaGateway -wsaSubnetMask $wsaSubnetMask -wsaFolder $wsaFolder

Start-Sleep 5

# Create a VM Group for the Standalone Workspace ONE Access Instance
logger "Creating a VM Group for the WSA Appliance"
$drsGroupName = "cmi-m01-vm-group-wsa"
$drsGroupVMs = "cmi-wsa01"

Add-ClusterGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -drsGroupName $drsGroupName -drsGroupVMs $drsGroupVMs

Start-Sleep 5

# Complete the Initial Configuration of the Standalone Workspace ONE Access Instance
logger "Initializing the WSA Appliance"
$wsaAdminPassword = "VMware123!"
$wsaRootPassword = "VMware123!"
$wsaSshUserPassword = "VMware123!"

Initialize-WorkspaceOne -wsaFqdn $wsaFqdn -adminPass $wsaAdminPassword -rootPass $wsaRootPassword -sshUserPass $wsaSshUserPassword

Start-Sleep 5

# Configure NTP on the Standalone Workspace ONE Access Instance - NO ADDITONAL VARIABLES
logger "Configuring NTP on the WSA Appliance"
Set-WorkspaceOneNtpConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaFqdn $wsaFqdn -rootPass $wsaRootPassword

Start-Sleep 5

# Replace the Certificate of the Standalone Workspace ONE Access Instance
# These are additional variables to point at the location of the certificate files needed for replacing the self signed certificate on the WSA Appliance
logger "Replacing the default certificate with a signed certificate"
$rootCaPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\RootCA\Root64.cer"
$wsaCertKeyPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\cmi-wsa01\cmi-wsa01.key"
$wsaCertPath = "C:\VLC\CertGenVVS\SignedByMSCACerts\cmi-wsa01\cmi-wsa01.7.crt"

Install-WorkspaceOneCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaFqdn $wsaFqdn -rootPass $wsaRootPassword -sshUserPass $wsaSshUserPassword -rootCa $rootCaPath -wsaCertKey $wsaCertKeyPath -wsaCert $wsaCertPath

Start-Sleep 5

# Configure SMTP on the Standalone Workspace ONE Access Instance
logger "Configuring the SMTP settings for the WSa Appliance"
$smtpServerFqdn = "smtp.elasticsky.org"
$smtpServerPort = "25"
$smtpEmailAddress = "cmi-wsa@elasticsky.org"

Set-WorkspaceOneSmtpConfig -server $wsaFqdn -user admin -pass $wsaAdminPassword -smtpFqdn $smtpServerFqdn -smtpPort $smtpServerPort -smtpEmail $smtpEmailAddress

Start-Sleep 5

# Configure Identity Source for the Standalone Workspace ONE Access Instance
logger "Configuring a connection between WSA and Active Directory"
$baseDnUsers = "OU=Security Users,dc=elasticsky,DC=org"
$baseDnGroups = "OU=Security Groups,dc=elasticsky,DC=org"
$wsaBindUserDn = "CN=svc-wsa-ad,OU=Security Users,dc=elasticsky,DC=org"
$wsaBindUserPassword = "VMware123!"
$adGroups = "gg-nsx-enterprise-admins","gg-nsx-network-admins","gg-nsx-auditors","gg-wsa-admins","gg-wsa-directory-admins","gg-wsa-read-only"

Add-WorkspaceOneDirectory -server $wsaFqdn -user admin -pass $wsaAdminPassword -domain $domainFqdn -baseDnUser $baseDnUsers -baseDnGroup $baseDnGroups -bindUserDn $wsaBindUserDn -bindUserPass $wsaBindUserPassword -adGroups $adGroups -certificate $rootCaPath -protocol ldaps

Start-Sleep 5

# Configure Local Password Policy for the Standalone Workspace ONE Access Instance
logger "Configuring WSA local password policy"
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

Request-WSAToken -fqdn $wsaFqdn -user admin -pass $wsaAdminPassword
Set-WSAPasswordPolicy -minLen $minLen -minLower $minLower -minUpper $minUpper -minDigit $minDigit -minSpecial $minSpecial -history $history -maxConsecutiveIdenticalCharacters $maxConsecutiveIdenticalCharacters -maxPreviousPasswordCharactersReused $maxPreviousPasswordCharactersReused -tempPasswordTtlInHrs $tempPasswordTtlInHrs -passwordTtlInDays $passwordTtlInDays -notificationThresholdInDays $notificationThresholdInDays -notificationIntervalInDays $notificationIntervalInDays | Get-WSAPasswordPolicy
Set-WSAPasswordLockout -numAttempts $numAttempts -attemptInterval $attemptInterval -unlockInterval $unlockInterval

Start-Sleep 5

# Assign Workspace ONE Access Roles to Active Directory Groups
logger "Assigning Active directory global groups to WSA admin groups"
$wsaSuperAdminGroup = "gg-wsa-admins"
$wsaDirAdminGroup = "gg-wsa-directory-admins"
$wsaReadOnlyGroup = "gg-wsa-read-only"

# Assign Workspace ONE Access Roles to Active Directory Groups
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaSuperAdminGroup -role "Super Admin"
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaDirAdminGroup -role "Directory Admin"
Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaReadOnlyGroup -role "ReadOnly Admin"

Start-Sleep 5

# The standalone Workspace ONE Access Appliance is now deployed and configured, ready for NSX-T Manager to be integrated for centralised identity management

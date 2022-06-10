############################################################################
# 
#        Private Cloud Automation for VMware Cloud Foundation
#
#         Words and Music by the VVS Team and Alasdair Carnie  
#
############################################################################

# Prerequisites

# Common Variables
$sddcManagerFqdn = "cmi-vcf01.elasticsky.org"
$sddcManagerUser = "administrator@vsphere.local"
$sddcManagerPass = "VMware123!"
$sddcDomainName = "cmi-m01"
$domain = "elasticsky.org"
$vraFqdn = "xint-vra01.elasticsky.org"
$vraUser = "configadmin"
$vraPass = "VMware123!"
$domainAlias = "elasticsky"
$vCenterFqdn = "cmi-w01-vc01.elasticsky.org"
$vCenterUser = "svc-vra-vsphere@elasticsky.org"
$vCenterPass = "VMware123!"

# Add the vRealize Automation License to vRealize Suite Lifecycle Manager
$licenseAlias = "vRealize Automation"
$licenseKey = "0J430-4NH5H-H83FA-080U6-95U0N"
New-vRSLCMLockerLicense -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $licenseAlias -license $licenseKey

# Import the Certificate for vRealize Automation to vRealize Suite Lifecycle Manager
$certificateAlias = "xint-vra01"
$certChain = "C:\VLC\CertGenVVS\SignedByMSCACerts\xint-vra01\xint-vra01.2.chain.pem"
Import-vRSLCMLockerCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -certChainPath $certChain -certificatePassphrase "VMware123!" -certificateAlias $certificateAlias

# Add the vRealize Automation Password to vRealize Suite Lifecycle Manager
$rootPasswordAlias = "vra-root"
$rootPassword = "VMware123!"
$rootUserName = "root"
$xintPasswordAlias = "xint-env-admin"
$xintPassword = "VMware123!"
$xintUserName = "admin"
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $rootPasswordAlias -password $rootPassword -userName $rootUserName
New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $xintPasswordAlias -password $xintPassword -userName $xintUserName

# Deploy vRealize Automation by Using vRealize Suite Lifecycle Manager
New-vRADeployment -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass 

# Create a Virtual Machine and Template Folder for the vRealize Automation Cluster Virtual Machines
$vraFolder = "xint-m01-fd-vra"
Add-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -folderName $vraFolder

# Move the vRealize Automation Cluster Virtual Machines to the Dedicated Folder
$vraVmList = "xint-vra01a,xint-vra01b,xint-vra01c"
$vraFolder = "xint-m01-fd-vra"
Move-VMtoFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -vmList $vraVmList -folder $vraFolder

# Create a Virtual Machine and Template Folder and a Resource Pool for the vRealize Automation-Managed Workloads on the VI Workload Domain vCenter Server
$sddcDomainName = "cmi-w01"
$vmFolder = "cmi-w01-fd-workload"
$resourcePoolName = "cmi-w01-cl01-rp-workload"
Add-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -folderName $vmFolder
Add-ResourcePool -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -resourcePoolName $resourcePoolName

# Configure a vSphere DRS Anti-Affinity Rule for the vRealize Automation Cluster Virtual Machines
$sddcDomainName = "cmi-w01"
$antiAffinityRuleName = "anti-affinity-rule-vra"
$antiAffinityVMs = "xint-vra01a,xint-vra01b,xint-vra01c"
Add-AntiAffinityRule -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -ruleName $antiAffinityRuleName -antiAffinityVMs $antiAffinityVMs

# Create a VM Group and Define the Startup Order of the vRealize Automation Cluster Virtual Machines
$drsGroupNameWsa = "xint-vm-group-wsa"
$drsGroupNameVra = "xint-vm-group-vra"
$ruleName = "vm-vm-rule-wsa-vra"
$drsGroupVMs = "xint-vra01a,xint-vra01b,xint-vra01c"
Add-ClusterGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -drsGroupName $drsGroupNameVra -drsGroupVMs $drsGroupVMs
Add-VmStartupRule -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -ruleName $ruleName -vmGroup  $drsGroupNameVra -dependOnVmGroup $drsGroupNameWsa

# Add the vRealize Automation Cluster Virtual Machines to the First Availability Zone VM Group
# $groupName = "primary_az_vmgroup"
# $vmList = "xint-vra01a,xint-vra01b,xint-vra01c"
# Add-VmGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -name $groupName -vmList $vmList

# Configure the Organization Settings for vRealize Automation
# Configure the Organization Name for vRealize Automation
$displayName = "Elasticsky"
Update-vRAOrganizationDisplayName -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -displayName $displayName -vraUser $vraUser -vraPass $vraPass

# Synchronize the Active Directory Groups for vRealize Automation in Workspace ONE Access
$wsaFqdn = "xint-wsa01a.elasticsky.org"
$wsaUser = "admin"
$wsaPass = "VMware123!"
$bindUser = "svc-wsa-ad"
$bindPass = "VMware123!"
$baseDnGroup = "OU=Security Groups,DC=elasticsky,DC=org"
$adGroups = "gg-vra-org-owners","gg-vra-cloud-assembly-admins","gg-vra-cloud-assembly-users","gg-vra-cloud-assembly-viewers","gg-vra-service-broker-admins","gg-vra-service-broker-users","gg-vra-service-broker-viewers","gg-vra-orchestrator-admins","gg-vra-orchestrator-designers","gg-vra-orchestrator-viewers"
Add-WorkspaceOneDirectoryGroup -server $wsaFqdn -user $wsaUser -pass $wsaPass -domain $domain -bindUser $bindUser -bindPass  $bindPass -baseDnGroup $baseDnGroup -adGroups $adGroups

# Assign Organization and Service Roles to the Groups for vRealize Automation
$orgOwner = "gg-vra-org-owners@elasticsky.org"
$cloudAssemblyAdmins = "gg-vra-cloud-assembly-admins@elasticsky.org"
$cloudAssemblyUsers = "gg-vra-cloud-assembly-users@elasticsky.org"
$cloudAssemblyViewers = "gg-vra-cloud-assembly-viewers@elasticsky.org"
$codeStreamAdmins = "gg-vra-code-stream-admins@elasticsky.org"
$codeStreamDevelopers = "gg-vra-code-stream-developers@elasticsky.org"
$codeStreamExecutors = "gg-vra-code-stream-executors@elasticsky.org"
$codeStreamUsers = "gg-vra-code-stream-users@elasticsky.org"
$codeStreamViewers = "gg-vra-code-stream-viewers@elasticsky.org"
$serviceBrokerAdmins = "gg-vra-service-broker-admins@elasticsky.org"
$serviceBrokerUsers = "gg-vra-service-broker-users@elasticsky.org"
$serviceBrokerViewers = "gg-vra-service-broker-viewers@elasticsky.org"
$orchestratorAdmins = "gg-vra-orchestrator-admins@elasticsky.org"
$orchestratorDesigners = "gg-vra-orchestrator-designers@elasticsky.org"
$orchestratorViewers = "gg-vra-orchestrator-viewers@elasticsky.org"
$saltStackAdmins = "gg-vra-salt-stack-admins@elasticsky.org"
$saltStackSuperusers = "gg-vra-salt-stack-superusers@elasticsky.org"
$saltStackUsers = "gg-vra-salt-stack-users@elasticsky.org"
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $orgOwner -orgRole org_owner
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $cloudAssemblyAdmins -orgRole org_member -serviceRole automationservice:cloud_admin
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $cloudAssemblyUsers -orgRole org_member -serviceRole automationservice:user
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $cloudAssemblyViewers -orgRole org_member -serviceRole automationservice:viewer
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $serviceBrokerAdmins -orgRole org_member -serviceRole catalog:admin
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $serviceBrokerUsers -orgRole org_member -serviceRole catalog:user
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $serviceBrokerViewers -orgRole org_member -serviceRole catalog:viewer
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $orchestratorAdmins -orgRole org_member -serviceRole orchestration:admin
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $orchestratorDesigners -orgRole org_member -serviceRole orchestration:designer
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $orchestratorViewers -orgRole org_member -serviceRole orchestration:viewer
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $saltStackAdmins -orgRole org_member -serviceRole saltstack:admin
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $saltStackSuperusers -orgRole org_member -serviceRole saltstack:superuser
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $saltStackUsers -orgRole org_member -serviceRole saltstack:user
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $codeStreamAdmins -orgRole org_member -serviceRole CodeStream:administrator
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $codeStreamDevelopers -orgRole org_member -serviceRole codestream:developer
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $codeStreamExecutors -orgRole org_member -serviceRole codestream:executor
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $codeStreamUsers -orgRole org_member -serviceRole codestream:user
Add-vRAGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -displayName $codeStreamViewers -orgRole org_member -serviceRole codestream:viewer

# Configure Service Account Privileges in vSphere and NSX Manager
# Define Custom Roles in vSphere for vRealize Automation and vRealize Orchestrator
$vraVsphereRoleName = "vRealize Automation to vSphere Integration"
$vroVsphereRoleName = "vRealize Orchestrator to vSphere Integration"
Add-vSphereRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -roleName $vraVsphereRoleName
# The default path for the vSphereRoles folder is C:\Program Files\WindowsPowerShell\Modules\PowerValidatedSolutions\<powervalidatedsolutions_version>\vSphereRoles.
Add-vSphereRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -roleName $vroVsphereRoleName

# Configure Service Account Permissions for the vRealize Automation and vRealize Orchestrator Integrations to vSphere
$domainFqdn = "elasticsky.org"
$domainBindUser = "svc-vsphere-ad"
$domainBindPass =  "VMware123!"
$vraServiceAccount = "svc-vra-vsphere"
$vraRole = "vRealize Automation to vSphere Integration"
$vroServiceAccount = "svc-vro-vsphere"
$vroRole = "vRealize Orchestrator to vSphere Integration"
Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vraServiceAccount -role $vraRole -propagate true -type user
Add-vCenterGlobalPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $vroServiceAccount -role $vroRole -propagate true -type user

# Restrict the vRealize Automation and vRealize Orchestrator Service Accounts Access to the Management Domain
$sddcDomainName = "cmi-m01"
$vraServiceAccount = "svc-vra-vsphere"
$vroServiceAccount = "svc-vro-vsphere"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vraServiceAccount -role "NoAccess"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vroServiceAccount -role "NoAccess"

# Restrict the vRealize Automation and vRealize Orchestrator Service Accounts Access to Virtual Machine and Datastore Folders in the VI Workload Domain
$sddcDomainName = "cmi-w01"
$vraServiceAccount = "svc-vra-vsphere"
$vroServiceAccount = "svc-vro-vsphere"
$nsxEdgeVMFolder = "cmi-w01-fd-edge"
$localDatastoreFolder = "cmi-w01-fd-ds-local"
$readOnlyDatastoreFolder = "cmi-w01-fd-ds-readonly"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vraServiceAccount -role "NoAccess" -folderName $nsxEdgeVMFolder -folderType "VM"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vraServiceAccount -role "NoAccess" -folderName $localDatastoreFolder -folderType "Datastore"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vraServiceAccount -role "NoAccess" -folderName $readOnlyDatastoreFolder -folderType "Datastore"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vroServiceAccount -role "NoAccess" -folderName $nsxEdgeVMFolder -folderType "VM"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vroServiceAccount -role "NoAccess" -folderName $localDatastoreFolder -folderType "Datastore"
Set-vCenterPermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $domainAlias -workloadDomain $sddcDomainName -principal $vroServiceAccount -role "NoAccess" -folderName $readOnlyDatastoreFolder -folderType "Datastore"

# Configure Service Account Permissions for the vRealize Automation to NSX-T Data Center Integration on the VI Workload Domain NSX Manager Cluster
$sddcDomainName = "cmi-w01"
$nsxVraUser = "svc-vra-nsx@elasticsky.org"
Add-NsxtVidmRole -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -type user -principal $nsxVraUser -role enterprise_admin

# Obtain an API Refresh Token for the vRealize Automation Terraform Provider by Using PowerShell
Request-vRAToken -fqdn $vraFqdn -username $vraUser -password $vraPass -displayToken
#vra_url = "https://xint-vra01.elasticsky.org"
#vra_api_token = "zFfQRlPV3CRanI0GXaEm7rTEjChO8Lxt"
#vra_insecure  = false

# Configure Cloud Assembly in vRealize Automation
# Add Cloud Accounts for the VI Workload Domains to vRealize Automation
$sddcDomainName = "cmi-w01"
$vraUser = "configadmin"
$vrPass = "VMware123!"
$capabilityTag = "private"
New-vRACloudAccount -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -vraUser $vraUser -vraPass $vrPass -capabilityTab $capabilityTag

# Configure the Cloud Zones in vRealize Automation
$tagKey = "enabled"
$tagValue = "true"
$vmFolder = "cmi-w01-fd-workload"
$resourcePoolName = "cmi-w01-cl01-rp-workload"
Update-vRACloudAccountZone -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -vraUser $vraUser -vraPass $vrPass -tagKey $tagKey -tagValue $tagValue -folder $vmFolder -resourcePool $resourcePoolName

# Configure Service Broker in vRealize Automation
# Configure Email Alerts in Service Broker
$smtpServer = "smtp.elasticsky.org"
$emailAddress = "vra-no-reply@elasticsky.org"
$senderName = "elasticsky Cloud"
Add-vRANotification -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vrPass -smtpServer $smtpServer -emailAddress $emailAddress -sender $senderName -connection NONE

# Configure vRealize Orchestrator in vRealize Automation
# Import the Trusted Certificates to vRealize Orchestrator
Add-vROTrustedCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass
# Navigate to the Root CA .cer certificate file and click Open

# Add the VI Workload Domain vCenter Server to vRealize Orchestrator
$vcUser = "svc-vro-vsphere@elasticsky.org"
$vcPass = "VMware123!"
Add-vROvCenterServer -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -vraUser $vraUser -vraPass $vraPass -vcUser $vcUser -vcPass $vcPass


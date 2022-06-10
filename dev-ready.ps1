######################################################################################################
# 
#          Implementation of Developer Ready Infrastructure for VMware Cloud Foundation
# 
#   You must have the VMware Validated Solutions PowerShell toolkit Installed to use this script
# 
#                       Words and Music By Alasdair Carnie and the VVS Team
# 
######################################################################################################

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

Logger "VVS - Developer Ready Infrastructure.  Brought to you by the VVS team, the letters L and F, and by the number 42"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager Variables
logger "Set the SDDC Manager variables"
$sddcManagerFqdn = "cmi-vcf01.elasticsky.org"
$sddcManagerUser = "administrator@vsphere.local"
$sddcManagerPass = "VMware123!"
$sddcDomainName = "cmi-w01"
$domain = "elasticsky.org"

# Configure NSX-T Data Center for Developer Ready Infrastructure

logger "Configure NSX-T with a segment for the Supervisor cluster and secure it with a prefix list and route map"

# Add a Network Segment for Developer Ready Infrastructure
logger "Creating the Segment"
$kubSegmentName = "cmi-w01-kub-seg01"
$wldTier1GatewayName = "cmi-w01-ec01-t1-gw01"
$kubSegmentGatewayCIDR = "192.168.20.1/24"
$overlayTzName = "overlay-tz-cmi-w01-nsx01.elasticsky.org"
Add-NetworkSegment -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -SegmentName $kubSegmentName -ConnectedGateway $wldTier1GatewayName -Cidr $kubSegmentGatewayCIDR -TransportZone $overlayTzName -GatewayType Tier1 -SegmentType Overlay

#Add IP Prefix Lists to the Tier-0 Gateway for Developer Ready Infrastructure
logger "Create the Prefix List and assign the CIDR Addresses"
$wldTier0GatewayName = "cmi-w01-ec01-t0-gw01"
$wldPrefixListName = "cmi-w01-ec01-t0-gw01-prefixlist"
$kubSegmentSubnetCidr = "192.168.20.0/24"
$ingressSubnetCidr = "10.70.0.0/24"
$egressSubnetCidr = "10.80.0.0/24"
Add-PrefixList -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -Tier0Gateway $wldTier0GatewayName -PrefixListName $wldPrefixListName -SubnetCIDR $kubSegmentSubnetCidr -ingressSubnetCidr $ingressSubnetCidr -egressSubnetCidr $egressSubnetCidr -GE "28" -LE "32" -Action PERMIT

#Create a Route Map on the Tier-0 Gateway for Developer Ready Infrastructure
logger "Create the Route Map and assign the Prefix List as it's source of truth"
$wldTier0GatewayName = "cmi-w01-ec01-t0-gw01"
$wldPrefixListName = "cmi-w01-ec01-t0-gw01-prefixlist"
$wldRouteMapName = "cmi-w01-ec01-t0-gw01-routemap"
Add-RouteMap -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -Tier0Gateway $wldTier0GatewayName -RouteMap $wldRouteMapName -PrefixListName $wldPrefixListName -Action PERMIT -ApplyPolicy:$True

#Configure the vSphere Environment for Developer Ready Infrastructure
#Assign a New Tag to the vSAN Datastore for Developer Ready Infrastructure
logger "Creating a Tag Category and Tag for storage being used by Tanzu"
$tagCategoryName = "vsphere-with-tanzu-category"
$tagName = "vsphere-with-tanzu-tag"
Set-DatastoreTag -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -TagName $tagName -TagCategoryName $tagCategoryName

#Create a Storage Policy that Uses the New vSphere Tag for Developer Ready Infrastructure
logger "Creating a tag based storage policy and assigning the tanzu tag to it"
$spbmPolicyName = "vsphere-with-tanzu-storage-policy"
$tagName = "vsphere-with-tanzu-tag"
Add-StoragePolicy -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -PolicyName $spbmPolicyName -TagName $tagName

#Create a Subscribed Content Library for Developer Ready Infrastructure
logger "Creating the TKGS vCenter Content library"
$contentLibraryName = "Kubernetes"
Add-ContentLibrary -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -ContentLibraryName $contentLibraryName -SubscriptionUrl "https://wp-content.vmware.com/v2/latest/lib.json"

# Deploy and Configure vSphere with Tanzu for Developer Ready Infrastructure

# Prerequisites
# While it is not an absolute, it is recommended that you deploy the IAS VVS before deploying Tanzu with Kubernetes.  This will enable you to leverage AD accounts when creating namespaces
# Install the vSphere kubectl plug-in to be able to connect to the Supervisor Cluster as a vCenter Single Sign-On user.

# Deploy a Supervisor Cluster for Developer Ready Infrastructure
logger "creating the Tanzu on vSphere configuration file"
$wmClusterInput = @{
    server = "cmi-vcf01.elasticsky.org"
    user = "administrator@vsphere.local"
    pass = 'VMware123!'
    domain = "cmi-w01"
    cluster = "cmi-w01-cl01"
    sizeHint = "Tiny"
    managementVirtualNetwork = "cmi-w01-kub-seg01"
    managementNetworkMode = "StaticRange"
    managementNetworkStartIpAddress = "192.168.20.10"
    managementNetworkAddressRangeSize = 5
    managementNetworkGateway = "192.168.20.1"
    managementNetworkSubnetMask = "255.255.255.0"
    masterDnsName = "cmi-w01-cl01.cmi.elasticsky.org"
    masterDnsServers = @("10.0.0.201")
    masterNtpServers = @("10.0.0.201")
    contentLibrary = "Kubernetes"
    ephemeralStoragePolicy = "vsphere-with-tanzu-storage-policy"
    imageStoragePolicy = "vsphere-with-tanzu-storage-policy"
    masterStoragePolicy = "vsphere-with-tanzu-storage-policy"
    nsxEdgeCluster = "cmi-w01-ec01"
    distributedSwitch = "cmi-w01-cl01-vds01"
    podCIDRs = "100.100.0.0/20"
    serviceCIDR = "100.200.0.0/22"
    externalIngressCIDRs = "10.70.0.0/24"
    externalEgressCIDRs = "10.80.0.0/24"
    workerDnsServers = @("10.0.0.201")
    masterDnsSearchDomain = "elasticsky.org"
   }

logger "Deploying Tanzu on vSphere"
Enable-SupervisorCluster @wmClusterInput

# Post Deployment, we are going to replace the default certificate with one signed by our Enterprise CA
# We will then deploy the integrated harbor repository and create a sample setup with a namespace and TKGS cluster

# Create a certificate request using the CSR template from Tanzu
logger "Creating CSR for Tanzu"

$ADServer = (Get-ADDomainController -Discover -ForceDiscover -Writable).HostName[0]
$RootDS = $((Get-ADRootDSE -Server $ADServer).configurationNamingContext)
$caPath = "CN=Certification Authorities,CN=Public Key Services,CN=Services,$RootDS"
$caLdapObj = Get-ADObject -SearchBase $caPath -LdapFilter "(ObjectClass=certificationAuthority)" -Properties * -Server $ADServer
$CAName = $ADServer + "\" + ($caLdapObj).CN

$wmClusterName = "cmi-w01-cl01"
$CommonName = "wcp-dev.elasticsky.org"
$Organization = "elasticSky"
$OrganizationalUnit = "IT"
$Country = "US"
$StateOrProvince = "Illinois"
$Locality = "Champaign"
$AdminEmailAddress = "admin@elasticsky.org"
$KeySize = 2048

New-SupervisorClusterCSR -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -cluster $wmClusterName -CommonName $CommonName -Organization $Organization -OrganizationalUnit $OrganizationalUnit -Country $Country -StateOrProvince $StateOrProvince -Locality $Locality -AdminEmailAddress $AdminEmailAddress -KeySize $Keysize -FilePath ".\SupervisorCluster.csr"


# The VVS does not currently have a function to request a certificate, so we have instered an extra function to make that happen
# You must have the certutil installed on the machine you are running the script from
logger "Sending CSR to Enterprise CA and requesting a certificate"
$csrFile = "./SupervisorCluster.csr"
$Template =  $(certutil -CATemplates -config $CAName | Where-Object {$_ -match "VMware"}).split(":")[0]
$certname = "supervisorcert.csr"
certreq -submit -config $CAName -attrib "CertificateTemplate:$Template" $csrFile $certname

# Install the newly created certificate
logger " Installing Tanzu certificate"
Install-SupervisorClusterCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -Cluster $wmClusterName -filePath $certname

# License the Supervisor Cluster for Developer Ready Infrastructure
# There is currently no VVS automation for replacing the licence for Tanzu, but you have 60 days to swap it out manually

# Deploy a Supervisor Namespace for Developer Ready Infrastructure
logger "Creating a sample namespace"
$wmClusterName = "cmi-w01-cl01"
$wmNamespaceName = "cmi-w01-ns01"
$spbmPolicyName = "vsphere-with-tanzu-storage-policy"
Add-Namespace -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -Cluster $wmClusterName -Namespace $wmNamespaceName -StoragePolicy $spbmPolicyName

# Assign the Supervisor Namespace Roles to Active Directory Groups
logger "Assigning permission to Active Directory global groups for admin and ready only roles"
$domainfqdn = "elasticsky.org"
$domainBindUser = "svc-vsphere-ad"
$domainBindPass = "VMware123!"
$wmNamespaceName = "cmi-w01-ns01"
$wmNamespaceEditUserGroup = "gg-kub-admins"
$wmNamespaceViewUserGroup = "gg-kub-readonly"
Add-NamespacePermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomainName -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -namespace $wmNamespaceName -principal $wmNamespaceEditUserGroup -role edit -type group
Add-NamespacePermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomainName -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -namespace $wmNamespaceName -principal $wmNamespaceViewUserGroup -role view -type group

# Enable the Registry Service on the Supervisor Cluster for Developer Ready Infrastructure
logger "Enabling the Harbor Registry service"
$spbmPolicyName = "vsphere-with-tanzu-storage-policy"
Enable-Registry -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -StoragePolicy $spbmPolicyName

# Deploy a Namespace for the Tanzu Kubernetes Cluster for Developer Ready Infrastructure
logger "Creating a namespace to deploy a sample TKGS cluster"
$wmClusterName = "cmi-w01-cl01"
$wmTkcNamespaceName = "cmi-w01-tkc01"
$spbmPolicyName = "vsphere-with-tanzu-storage-policy"
Add-Namespace -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -Cluster $wmClusterName -Namespace $wmTkcNamespaceName -StoragePolicy $spbmPolicyName

# Assign the New Tanzu Cluster Namespace Roles to Active Directory Groups
logger "Assigning permissions to Active Directory global groups in the TKGS namespace for admin and read only roles"
$domainfqdn = "elasticsky.org"
$domainBindUser = "svc-vsphere-ad"
$domainBindPass = "VMware123!"
$wmTkcNamespaceName = "cmi-w01-tkc01"
$wmNamespaceEditUserGroup = "gg-kub-admins"
$wmNamespaceViewUserGroup = "gg-kub-readonly"
Add-NamespacePermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomainName -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -namespace $wmTkcNamespaceName -principal $wmNamespaceEditUserGroup -role edit -type group
Add-NamespacePermission -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomainName -domain $domainFqdn -domainBindUser $domainBindUser -domainBindPass $domainBindPass -namespace $wmTkcNamespaceName -principal $wmNamespaceViewUserGroup -role view -type group

# Enable a Virtual Machine Class for the Tanzu Kubernetes Cluster for Developer Ready Infrastructure
logger "Assigning TKGS T-Shirt sizes to the namespace"
$wmNamespaceName = "cmi-w01-tkc01"
$vmClass1 = "guaranteed-small"
$vmClass2 = "best-effort-small"

Add-NamespaceVmClass -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -Namespace $wmNamespaceName -VMClass $vmClass1
Add-NamespaceVmClass -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -Namespace $wmNamespaceName -VMClass $vmClass2

# Provision a Tanzu Kubernetes Cluster for Developer Ready Infrastructure
logger "Provisioning a best effort small TKGS cluster"
$wmClusterName = "cmi-w01-cl01"
$wmTkcNamespaceName = "cmi-w01-tkc01"
$spbmPolicyName = "vsphere-with-tanzu-storage-policy"
$kubectlBinLocation = "c:\windows\system32"
# $env:PATH = "$kubectlBinLocation;$env:PATH"
$YAML = "$kubectlBinLocation\cmi-w01-tkc01.yaml"
$content = @"
apiVersion: run.tanzu.vmware.com/v1alpha1
kind: TanzuKubernetesCluster
metadata:
  name: $wmTkcNamespaceName
  namespace: $wmTkcNamespaceName
spec:
  topology:
    controlPlane:
      count: 3
      class: guaranteed-small
      storageClass: $spbmPolicyName
    workers:
      count: 3
      class: best-effort-small
      storageClass: $spbmPolicyName
  distribution:
    version: v1.20
  settings:
    network:
      cni:
        name: antrea
      services:
        cidrBlocks: ["198.51.100.0/12"]
      pods:
        cidrBlocks: ["192.0.2.0/16"]
"@

$content | Out-File $YAML
Add-TanzuKubernetesCluster -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -Cluster $wmClusterName -YAML $YAML

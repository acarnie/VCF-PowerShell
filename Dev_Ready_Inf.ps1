# Checking that the PowerShell Modules required for configurarion are installed
Install-Module -Name VMware.PowerCLI -MinimumVersion 12.3.0
Install-Module -Name VMware.vSphere.SsoAdmin -MinimumVersion 1.3.1
Install-Module -Name PowerVCF -MinimumVersion 2.1.3
Install-Module -Name PowerValidatedSolutions -MinimumVersion 1.0.0
Install-Module -Name Posh-SSH -RequiredVersion 2.0.2

Import-Module -Name VMware.PowerCLI
Import-Module -Name PowerValidatedSolutions
Import-Module -Name VMware.vSphere.SsoAdmin
Import-Module -Name PowerVCF
Import-Module -Name Posh-SSH -RequiredVersion 2.0.2

#Global Variables
$sddcManagerFqdn = "cmi-vcf01.elasticsky.org"
$sddcManagerUser = "administrator@vsphere.local"
$sddcManagerPass = "VMware123!"

$sddcDomainName = "cmi-m01"

$cluster = "cmi-m01-cl01"
$policy = "retry=5 min=disabled,disabled,disabled,disabled,15"

$wsaFqdn = "cmi-wsa01.elasticsky.org"
$wsaAdminPassword = "VMware123!"

$kubSegmentName = "cmi-m01-kub-seg01"
$wldTier1GatewayName = "cmi-m01-ec01-t1-gw01"
$kubSegmentGatewayCIDR = "192.168.20.1/24"
$overlayTzName = "cmi-m01-tz-overlay01"

$wldTier0GatewayName = "cmi-m01-ec01-t0-gw01"
$wldPrefixListName = "cmi-m01-ec01-t0-gw01-prefixlist"
$kubSegmentSubnetCidr = "192.168.20.0/24"
$ingressSubnetCidr = "10.70.0.0/24"
$egressSubnetCidr = "10.80.0.0/24"

$wldRouteMapName = "cmi-m01-ec01-t0-gw01-routemap"

$tagCategoryName = "vsphere-with-tanzu-category"
$tagName = "vsphere-with-tanzu-tag"

$spbmPolicyName = "vsphere-with-tanzu-storage-policy"

$contentLibraryName = "Kubernetes"

# *******************************************************************************************************************************************
# This part of the script will perform parts of the Identity and Access Management VMware Validated Solution specific to VI Workload Domains
# *******************************************************************************************************************************************

# Configure ESXi Hosts Password and Lockout Policies
Set-EsxiPasswordPolicy -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -cluster $cluster -policy $policy

# Integrate NSX-T Data Center with the Standalone Workspace ONE Access Instance
Set-WorkspaceOneNsxtIntegration -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -wsaFqdn $wsaFqdn -wsaUser admin -wsaPass $wsaAdminPassword

# *******************************************************************************************************************************************
# This part of the script will configure the environment for Tanzu on vSphere and then deploy it.
# *******************************************************************************************************************************************

# Add a Network Segment for Developer Ready Infrastructure
Add-NetworkSegment -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -SegmentName $kubSegmentName -ConnectedGateway $wldTier1GatewayName -Cidr $kubSegmentGatewayCIDR -TransportZone $overlayTzName -GatewayType Tier1 -SegmentType Overlay

# Add IP Prefix Lists to the Tier-0 Gateway for Developer Ready Infrastructure
Add-PrefixList -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -Tier0Gateway $wldTier0GatewayName -PrefixListName $wldPrefixListName -SubnetCIDR $kubSegmentSubnetCidr -ingressSubnetCidr $ingressSubnetCidr -egressSubnetCidr $egressSubnetCidr -GE "28" -LE "32" -Action PERMIT

# Create a Route Map on the Tier-0 Gateway for Developer Ready Infrastructure
Add-RouteMap -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -Tier0Gateway $wldTier0GatewayName -RouteMap $wldRouteMapName -PrefixListName $wldPrefixListName -Action PERMIT -ApplyPolicy:$True

# Assign a New Tag to the vSAN Datastore for Developer Ready Infrastructure
Set-DatastoreTag -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -TagName $tagName -TagCategoryName $tagCategoryName

# Create a Storage Policy that Uses the New vSphere Tag for Developer Ready Infrastructure
Add-StoragePolicy -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -PolicyName $spbmPolicyName -TagName $tagName

# Create a Subscribed Content Library for Developer Ready Infrastructure
Add-ContentLibrary -Server $sddcManagerFqdn -User $sddcManagerUser -Pass $sddcManagerPass -Domain $sddcDomainName -ContentLibraryName $contentLibraryName -SubscriptionUrl "https://wp-content.vmware.com/v2/latest/lib.json"

# Deploy and Configure vSphere with Tanzu for Developer Ready Infrastructure

$clusterInput = @{
    Server = "cmi-vcf01.elasticsky.org"                
    User = "administrator@vsphere.local"
    Pass = "VMware123!"                                
    Domain = "cmi-m01"
    SizeHint = "Small"                       
    ManagementVirtualNetwork = "cmi-m01-kub-seg01"
    ManagementNetworkMode = "StaticRange"
    ManagementNetworkStartIpAddress = "192.168.20.10"
    ManagementNetworkAddressRangeSize = "5"
    ManagementNetworkGateway = "192.168.20.1"
    ManagementNetworkSubnetMask = "255.255.255.0"
    Cluster = "cmi-m01-cl01"
    ContentLibrary = "Kubernetes"
    EphemeralStoragePolicy = "vsphere-with-tanzu-storage-policy"
    ImageStoragePolicy = "vsphere-with-tanzu-storage-policy"
    MasterStoragePolicy = "vsphere-with-tanzu-storage-policy"
    NsxEdgeCluster = "cmi-m01-ec01"
    DistributedSwitch = "cmi-m01-cl01-mgmt"
    PodCIDRs = "100.100.0.0/20"
    ServiceCIDR = "10.200.0.0/22"
    ExternalIngressCIDRs = "10.70.0.0/24"
    ExternalEgressCIDRs = "10.80.0.0/24"
    NtpServer1IpAddress = "10.0.0.201"
    NtpServer2IpAddress = "10.0.0.202"
    DnsServer1IpAddress = "10.0.0.201"
    DnsServer2IpAddress = "10.0.0.202"
    MasterDnsSearchDomain = "elasticsky.org"
}

Enable-SupervisorCluster @clusterInput -async true
# ====================================================================================
#                 VMware Cloud Foundation Post BringUp Configuration                 
#                                                                                    
#      You must have PowerVCF and PowerCLI installed in order to use this script     
#                                                                                    
#                   Words and Music By Ben Sier and Alasdair Carnie                      
# ====================================================================================

# Variables for the execution log file and json file directories.
Clear-Host
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

logger "VCF Certificate Configuration.  Brought to you by the letters L and F, and by the number 42"

Start-Process powershell -Argumentlist "`$host.UI.RawUI.WindowTitle = 'VLC Logging window';Get-Content '$logfile' -wait"

# SDDC Manager variables.  Details could be pulled from the PnP Workbook
logger "Setting Variables for SDDC Manager"
$sddcManagerfqdn = "cmi-vcf01.elasticsky.org"
$ssoUser = "administrator@vsphere.local"
$ssoPass = "VMware123!"
$sddcMgrVMName = $sddcManagerfqdn.Split('.')[0] # If maintaining static values would suggest this method, this way single input
# $sddcMgrVMName = "cmi-vcf01"
$sddcUser = "root"
$sddcPassword = "VMware123!"

# Authenticate to SDDC Manager using global variables defined at the top of the script
if (Test-VCFConnection -server $sddcManagerfqdn) {
    if (Test-VCFAuthentication -server $sddcManagerfqdn -user $ssoUser -pass $ssoPass) { 

        # ==================== Configure Microsoft Certificate Authority Integration, and create and deploy certificates for vCenter, NSX-T and SDDC Manager ====================

        # Setting Microsoft CA Variables for adding the CA to SDDC Manager [Gary] Details could be pulled from the PnP Workbook
        logger "Setting Variables for Configuring the Microsoft CA"
        $mscaUrl = "https://es-dc-01.elasticsky.org/certsrv"
        $mscaUser = "svc-vcf-ca@elasticsky.org"
        $mscaPassword = "VMware123!"

        # Register Microsoft CA with SDDC Manager
        if (!(Get-VCFCertificateAuthority).username) {
            logger "Registering the Microsoft CA with SDDC Manager"
            Set-VCFMicrosoftCA -serverUrl $mscaUrl -username $mscaUser -password $mscaPassword -templateName VMware
            Start-Sleep 5
        } else {
            logger "Registering Microsoft CA with SDDC Manager Already Configured"
        }

        # Setting Certificate Variables.  Details could be pulled from the PnP Workbook
        logger "Setting Variables for Certificate Replacement"
        $domainName = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty name
        $vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters
        $vcenter | Add-Member -Type NoteProperty -Name Type -Value "VCENTER"
        $nsxTCluster = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty nsxtCluster
        $nsxTCluster | Add-Member -MemberType NoteProperty -Name Type -Value "NSXT_MANAGER"
        $sddcCertManager = Get-VCFManager | Select-Object id, fqdn
        $sddcCertManager | Add-Member -MemberType NoteProperty -Name Type -Value "SDDC_MANAGER"
        $country = "us"
        $keySize = "2048"
        $keyAlg = "RSA"
        $locality = "Champaign"
        $org = "ElasticSky"
        $orgUnit = "IT"
        $state = "IL"
        $email = "administrator@elasticsky.org"

        if (!(Get-VCFCertificate -domainName $domainName -resources | Select-Object IssuedBy | Where-Object {$_ -match 'DC='+($mscaUrl.Split('.'))[1]})) {
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
            logger "Generating Certificates on CA for $domainName"
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
        } else {
            logger "Installation of Microsoft CA Signed Certificates Already Performed"
        }

        # ==================== Configure SDDC Manager Backup ====================
        $vcenter = Get-VCFWorkloadDomain | Where-Object { $_.type -match "MANAGEMENT" } | Select-Object -ExpandProperty vcenters
        Connect-VIServer -server $vcenter.fqdn -user $ssoUser -password $ssoPass | Out-Null

        # Variables for configuring the SDDC Manager and NSX-T Manager Backups
        logger "Setting Variables for Backup and extracting SSH Key for Backup User"
        $backupServer = "10.0.0.221"
        $backupPort = "22"
        $backupPath = "/home/admin"
        $backupUser = "admin"
        $backupPassword = "VMware123!"
        $backupProtocol = "SFTP"
        $backupPassphrase = "VMware123!VMware123!"

        if ((Get-VCFBackupConfiguration | Select-Object server).server -ne $backupServer) { 
            $getKeyCommand = "ssh-keygen -lf <(ssh-keyscan $backupServer 2>/dev/null) | grep '2048 SHA256'"
            $keyCommandResult = Invoke-VMScript -ScriptType bash -GuestUser $sddcUser -GuestPassword $sddcPassword -VM $sddcMgrVMName -ScriptText $getKeyCommand -ErrorVariable ErrMsg
            $backupKey = $($keyCommandResult.Split()[1])

            # Creating Backup Config JSON file
            logger "Create Backup Configuration JSON Specification"
            $backUpConfigurationSpec = [PSCustomObject]@{
                backupLocations = @(@{server = $backupServer; username = $backupUser; password = $backupPassword; port = $backupPort; protocol = $backupProtocol; directoryPath = $backupPath; sshFingerprint = $backupKey })
                backupSchedules = @(@{frequency = 'HOURLY'; resourceType = 'SDDC_MANAGER'; minuteOfHour = '0' })
                encryption      = @{passphrase = $backupPassphrase }
            }
            logger "Creating Backup Configuration JSON file"
            $backUpConfigurationSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\backUpConfigurationSpec.json

            # Configuring SDDC Manager Backup settings
            logger "Configuring SDDC Manager Backup Settings"
            $confVcfBackup = Set-VCFBackupConfiguration -json $($backUpConfigurationSpec | ConvertTo-Json -Depth 10)
            do { $taskStatus = Get-VCFTask -id $($confVcfBackup.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
        } else {
            logger "Reconfiguration of Backup Already Performed"
        }

        # ==================== Configure Repository ====================

        # Variables for configuring the SDDC Manager Depot
        logger "Setting Variables for Configuring SDDC Manager Depot"
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
        logger "Writing Changes to SDDC Manager Lifecycle Manager and Restarting LCM Service"
        Invoke-VMScript -ScriptType bash -GuestUser $sddcUser -GuestPassword $sddcPassword -VM $sddcMgrVMName -ScriptText $lcmChangeScript -ErrorVariable ErrMsg | Out-Null
        $pollLoopCounter = 0
        Do {
            if ($pollLoopCounter % 10 -eq 0) {
                logger "Waiting for the LCM Service to Restart"
            }
            $scriptCommand = 'curl http://localhost/lcm/about'
            $output = Invoke-VMScript -VM $sddcMgrVMName -ScriptText $scriptCommand -GuestUser $sddcUser -GuestPassword $sddcPassword -ErrorVariable ErrMsg
            if ($output.ScriptOutput.Contains("502")) {
                if (($pollLoopCounter % 10 -eq 0) -AND ($pollLoopCounter -gt 9)) {
                    LogMessage -Type ADVISORY -Message "LCM Service Restart Still in Progress"
                }
                Start-Sleep 20
                $pollLoopCounter ++
            }
        }
        While ($output.ScriptOutput.Contains("502"))
        logger "LCM Service Restart Completed"

        # Set Depot credentials in SDDC Manager
        if ((Get-VCFDepotCredential).username -ne $depotUser) {
            logger "Configuring the Bundle Depot Credentials in SDDC Manager"
            Set-VCFDepotCredential -username $depotUser -password $depotPassword | Out-Null
        } else {
            logger "Depot Credentials Already Configured"
        }

        # ==================== Check for the existance of AVNs and create them if required =======================

        # Variables to check for the existance of AVNs, and to create them if required.
        logger "Setting Variables for Configuring Application Virtual Networking (AVN)"
        $avnsLocalGw = "10.50.0.1"
        $avnsLocalMtu = "8000"
        $avnsLocalName = "region-seg-01"
        $avnsLocalRouterName = "cmi-m01-ec01-t1-gw01"
        $avnsLocalSubnet = "10.50.0.0"
        $avnsLocalSubnetMask = "255.255.255.0"

        $avnsXRegGw = "10.60.0.1"
        $avnsXRegMtu = "8000"
        $avnsXRegName = "xregion-seg01"
        $avnsXRegRouterName = "cmi-m01-ec01-t1-gw01"
        $avnsXRegSubnet = "10.60.0.0"
        $avnsXRegSubnetMask = "255.255.255.0"

        # Get the Edge Cluster ID
        logger "Getting the Edge Cluster ID"
        $edgeClusterId = Get-VCFEdgeCluster | Select-Object -ExpandProperty id

        # Create AVN Configration JSON file
        logger "Creating Application Virtual Networks (AVN) Configuration JSON file"
        $avnjson = [PSCustomObject]@{
            avns= @(@{gateway = $avnsLocalGw; mtu= $avnsLocalMtu ;name= $avnsLocalName ;regionType= 'REGION_A'; routerName= $avnsLocalRouterName ;subnet= $avnsLocalSubnet ; subnetMask= $avnsLocalSubnetMask }
                @{gateway= $avnsXRegGw; mtu= $avnsXRegMtu ;name= $avnsXRegName ;regionType= 'X_REGION';routerName= $avnsXRegRouterName ;subnet= $avnsXRegSubnet ; subnetMask= $avnsXRegSubnetMask })
            edgeClusterId = $edgeClusterId
        }
        $avnjson | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\avns.json
        
        # Deploy the AVN Configuration
        if (!(Get-VCFApplicationVirtualNetwork)) {
            logger "Deploying Application Virtual Networks (AVN) on Edge Cluster"
            logger "Validating Application Virtual Networks (AVN) JSON"
            $avnValidation = Add-VCFApplicationVirtualNetwork -json (Get-Content -Raw $jsonPathDir\avns.json) -validate
            if ($avnValidation.resultStatus -eq "SUCCEEDED") {
                $avnDeploy = Add-VCFApplicationVirtualNetwork -json (Get-Content -Raw $jsonPathDir\avns.json)
                do { $taskStatus = Get-VCFTask -id $($avnDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
                if (Get-VCFApplicationVirtualNetwork) {
                    logger "Application Virtual Networks (AVN) Deployed Successfully"
                }
            }
        } else {
            logger "Application Virtual Networks (AVN) Already Configured"
        }

        # ==================== Download and Depoloy vRealize Lifecycle Manager ====================

        # Create variable which identifies the vRealize Suite Lifecycle Manager Bundle
        do { $vrslcmBundle = Get-VCFBundle | Where-Object { $_.description -Match "vRealize Suite Lifecycle Manager" } } until ($null -ne $vrslcmBundle )

        # Download the vRealize Suite Lifecycle Manager Bundle and monitor the task until comleted
        if ((Get-VCFBundle -id $vrslcmBundle.id).downloadStatus -ne 'SUCCESSFUL') {
            logger "vRealize Suite Lifecycle Manager Download Requested"
            $requestBundle = Request-VCFBundle -id $vrslcmBundle.id
            Start-Sleep 5
            do { $taskStatus = Get-VCFTask -id $($requestBundle.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
            logger "vRealize Suite Lifecycle Manager Download Complete"
        } else {
            logger "vRealize Suite Lifecycle Manager Bundle Already Downloaded"
        }

        # Variables for VRSLCM
        logger "Setting Variables for vRealize Suite Lifecycle Manager Deployment"
        $vrslcmFqdn = "xint-vrslcm01.elasticsky.org"
        $vrslcmApiPass = 'VMware123!'
        $vrlscmSshPass = 'VMware123!'
        $vrslcmIp = '10.60.0.250'

        if (!(Get-VCFvRSLCM)) {
            # Create the JOSN Specification for vRealize Suite Lifecyclec Manager Deployment
            logger "Creating vRealize Suite Lifecycle Manager JSON File"
            $vrslcmDepSpec = [PSCustomObject]@{apiPassword = $vrslcmApiPass; fqdn = $vrslcmFqdn; nsxtStandaloneTier1Ip = $vrslcmIp; sshPassword = $vrlscmSshPass }
            $vrslcmDepSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\vrslcmDepSpec.json

            # Validate vRealize Suite Lifecyclec Manager Settings
            logger "Validating the vRealize Suite Lifecycle Manager JSON"
            $vrslcmValidate = New-VCFvRSLCM -json $jsonPathDir\vrslcmDepSpec.json -validate
            Start-Sleep 5
            do { $taskStatus = Get-VCFTask -id $($vrslcmValidate.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
            logger "Validation of the vRealize Suite Lifecycle Manager JSON Completed Successfully"

            # Deploy vRealize Suite Lifecycle Manager
            $vrslcmDeploy = New-VCFvRSLCM -json $jsonPathDir\vrslcmDepSpec.json
            logger "Deploying vRealize Suite Lifecycle Manager"
            Start-Sleep 5
            do { $taskStatus = Get-VCFTask -id $($vrslcmDeploy.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
            logger "Deployment Completed Successfully"
        } else {
            logger "vRealize Suite Lifecycle Manager Already Deployed"
        }

        # ==================== Create and deploy Certificate for vRSLCM ====================

        $vrslcm = Get-VCFvRSLCM
        $vrslcm | Add-Member -Type NoteProperty -Name Type -Value "VRSLCM"

        if (!(((Get-VCFCertificate -domainName $domainName -resources | Where-Object {$_.issuedTo -eq $vrslcmFqdn}).IssuedBy) -match 'DC='+($mscaUrl.Split('.'))[1])) {            # Create JSON Specification for vRSLCM Certificate Signing Request
            logger "Creating vRealize Suite Lifecycle Manager JSON Specification for Certificate Signing Request"
            $csrVrslcm = New-Object -TypeName PSCustomObject 
            $csrVrslcm | Add-Member -NotePropertyName csrGenerationSpec -NotePropertyValue @{country = $country; email = $email; keyAlgorithm = $keyAlg; keySize = $keySize; locality = $locality; organization = $org; organizationUnit = $orgUnit; state = $state }
            $csrVrslcm | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vrslcm.fqdn; name = $vrslcm.fqdn; sans = @($vrslcm.fqdn); resourceID = $vrslcm.id; type = $vrslcm.Type })
            $csrVrslcm | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\csrVrslcm.json

            # Generate CSR for vRSLCM Certificate
            logger "Requesting vRealize Suite Lifecycle Manager CSR for $domainName"
            $csrVrslcmReq = Request-VCFCertificateCSR -domainName $domainName -json $jsonPathDir\csrVrslcm.json
            do { $taskStatus = Get-VCFTask -id $($csrVrslcmReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

            # Create JSON Specification for vRSLCM Certificate Generation
            logger "Creating vRealize Suite Lifecycle Manager JSON specification for Certificate Request"
            $certVrslcmSpec = New-Object -TypeName PSCustomObject 
            $certVrslcmSpec | Add-Member -NotePropertyName caType -NotePropertyValue "Microsoft"
            $certVrslcmSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vrslcm.fqdn; name = $vrslcm.fqdn; sans = @($vrslcm.fqdn); resourceID = $vrslcm.id; type = $vrslcm.type })
            $certVrslcmSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certVrslcmSpec.json


            logger "Generating vRealize Suite Lifecycle Manager Certificate on CA for $domainName"
            $certVrslcmCreateReq = Request-VCFCertificate -domainName $domainName -json $jsonPathDir\certVrslcmSpec.json
            do { $taskStatus = Get-VCFTask -id $($certVrslcmCreateReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")

            # Install certificate on vRSLCM
            $certVrslcmInstallSpec = New-Object -TypeName PSCustomObject
            $certVrslcmInstallSpec | Add-Member -NotePropertyName operationType -NotePropertyValue "INSTALL"
            $certVrslcmInstallSpec | Add-Member -NotePropertyName resources -NotePropertyValue @(@{fqdn = $vrslcm.fqdn; name = $vrslcm.fqdn; sans = @($vrslcm.fqdn); resourceID = $vrslcm.id; type = $vrslcm.type })
            $certVrslcmInstallSpec | ConvertTo-Json -Depth 10 | Out-File -Filepath $jsonPathDir\certVrslcmInstallSpec.json

            logger "Installing vRealize Suite Lifecycle Manager Certificates for $domainName"
            $certVrslcmInstallReq = Set-VCFCertificate -domainName $domainName -json $jsonPathDir\certVrslcmInstallSpec.json
            do { $taskStatus = Get-VCFTask -id $($certVrslcmInstallReq.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
            logger "vRealize Suite Lifecycle Manager Certificate successfully installed"
        } else {

        }
        Disconnect-VIServer * -Confirm:$false -WarningAction SilentlyContinue | Out-Null
    }
}
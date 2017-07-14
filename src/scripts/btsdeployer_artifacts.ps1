<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Remote BizTalk Artifacts Disabler/Enabler
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Remote BizTalk Artifacts Disabler/Enabler
.NOTES
    File Name      : btsdeployer_artifacts.ps1
    Author         : Willians Schallemberger Schneider, @schalleneider
    Prerequisite   : PowerShell v3
#>

[CmdletBinding()]
param
(
    [parameter(mandatory = $true)]
    [PSObject]
        $server,
	
    [parameter(mandatory = $true)]
    [PSObject[]]
        $settings,

    [parameter(mandatory = $true)]
    [PSObject]
        $artifacts,
    
    [parameter(mandatory = $true)]
    [bool]
        $enableArtifacts
)

begin
{
    function Get-BizTalkConnectionString
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject]
                $server
        )

        process
        {
            $biztalkRegistryPath = "HKLM:\SOFTWARE\Microsoft\BizTalk Server\3.0\Administration"

            if (Test-Path -Path $biztalkRegistryPath)
            {
                $biztalkRegistryKey = Get-ItemProperty -Path $biztalkRegistryPath

                $mgmtDatabaseName  = $biztalkRegistryKey.MgmtDBName
                $mgmtDatabaseServer= $biztalkRegistryKey.MgmtDBServer
        
                if ($mgmtDatabaseName -ne $null -and $mgmtDatabaseServer -ne $null)
                {
                    return ("Server={0};Database={1};Integrated Security=SSPI" -f $mgmtDatabaseServer, $mgmtDatabaseName)
                }
                else
                {
                    [System.Environment]::NewLine + "   [{0}] BizTalk database name and server were not found." -f $server.Hostname | Write-Host -ForegroundColor Red
                }
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] BizTalk registry key was not found." -f $server.Hostname | Write-Host -ForegroundColor Red
            }
        }
    }

    function Build-WhereClauseFromProperties
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [System.Management.Automation.PSPropertyInfo[]]
                $properties
        )

        begin
        {
            $conditionList = New-Object System.Collections.ArrayList
        }

        process
        {
            $properties | % {
                $conditionItem = "`$_.{0} -eq '{1}'" -f $_.Name, $_.Value
                $conditionList.Add($conditionItem) > $null
            }
        }

        end
        {
            # Debug > $conditionList | % { Write-Host $_ -ForegroundColor Magenta }
            $clauseScript = $conditionList -Join " -and "
            return [ScriptBlock]::Create($clauseScript)
        }
    }

    function Get-ReceiveLocations()
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer]
                $biztalkCatalog
        )

        begin
        {
            $objReceiveLocations = New-Object System.Collections.ArrayList
        }

        process
        {
            $biztalkCatalog.ReceivePorts | % {
                $catalogReceivePort = $_
                $catalogReceivePort.ReceiveLocations | % {
                    $objReceiveLocation = New-Object PSObject -Property @{
                        Name = $_.Name
                        Enabled = $_.Enable
                        ReceivePort = $catalogReceivePort.Name
                        Application = IIf $catalogReceivePort.Application { $_.Name }
                        TransportType = IIf $_.TransportType { $_.Name }
                        ReceiveHandler = IIf $_.ReceiveHandler { $_.Name }
                        Artifact = $_
                    }
                    $objReceiveLocations.Add($objReceiveLocation) > $null
                }
            }
        }

        end
        {
            # Debug > $objReceiveLocations | % { Write-Host "ReceiveLocation: [" $_.Name "][" $_.Enabled "][" $_.ReceivePort "][" $_.Application "][" $_.TransportType "][" $_.ReceiveHandler "]" -ForegroundColor Magenta } 
            return $objReceiveLocations
        }
    }

    function Get-SendPorts()
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer]
                $biztalkCatalog
        )

        begin
        {
            $objSendPorts = New-Object System.Collections.ArrayList
        }

        process
        {
            $biztalkCatalog.SendPorts | % {
                $objSendPort = New-Object PSObject -Property @{
                    Name = $_.Name
                    Enabled = $_.Status -eq [Microsoft.BizTalk.ExplorerOM.PortStatus]::Started
                    Application = IIf $_.Application { $_.Name }
                    TransportType = IIf $_.PrimaryTransport { IIf $_.TransportType { $_.Name } }
                    SendHandler = IIf $_.PrimaryTransport { IIf $_.SendHandler { $_.Name } }
                    Artifact = $_
                }
                $objSendPorts.Add($objSendPort) > $null
            }
        }

        end
        {
            # Debug > $objSendPorts | % { Write-Host "SendPort: [" $_.Name "][" $_.Enabled "][" $_.Application "][" $_.TransportType "][" $_.SendHandler "]" -ForegroundColor Magenta } 
            return $objSendPorts
        }
    }

    function Get-Orchestrations()
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer]
                $biztalkCatalog
        )

        begin
        {
            $objOrchestrations = New-Object System.Collections.ArrayList
        }

        process
        {
            $biztalkCatalog.Applications | % {
                $catalogApplication = $_
                $catalogApplication.Orchestrations | % {
                    $objOrchestration = New-Object PSObject -Property @{
                        Name = $_.FullName
                        Enabled = $_.Status -eq [Microsoft.BizTalk.ExplorerOM.OrchestrationStatus]::Started
                        Application = IIf $_.Application { $_.Name }
                        Host = IIf $_.Host { $_.Name }
                        Artifact = $_
                    }
                    $objOrchestrations.Add($objOrchestration) > $null
                }
            }
        }

        end
        {
            # Debug > $objOrchestrations | % { Write-Host "Orchestrations: [" $_.Name "][" $_.Enabled "][" $_.Application "][" $_.Host "]" -ForegroundColor Magenta } 
            return $objOrchestrations
        }
    }

    function Get-Applications()
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer]
                $biztalkCatalog
        )

        begin
        {
            $objApplications = New-Object System.Collections.ArrayList
        }

        process
        {
            $biztalkCatalog.Applications | % {
                $objApplication = New-Object PSObject -Property @{
                    Name = $_.Name
                    Enabled = $_.Status -eq [Microsoft.BizTalk.ExplorerOM.Status]::Started
                    Artifact = $_
                }
                $objApplications.Add($objApplication) > $null
            }
        }

        end
        {
            # Debug > $objApplications | % { Write-Host "Applications: [" $_.Name "][" $_.Enabled "]" -ForegroundColor Magenta } 
            return $objApplications
        }
    }

    function Filter-Artifacts
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject[]]
                $objArtifacts,

            [parameter(mandatory = $true)]
            [AllowEmptyCollection()]
            [PSObject[]]
                $artifacts,

            [parameter(mandatory = $true)]
            [bool]
                $enabledArtifacts
        )

        begin
        {
            $filterArtifacts = New-Object System.Collections.ArrayList
        }

        process
        {
            $artifacts | % {
                $artifact = $_
                $objArtifacts | ? { $_.Enabled -eq $enabledArtifacts } | ? -FilterScript (Build-WhereClauseFromProperties $artifact.PSObject.Properties) | % {
                    $filterArtifacts.Add($_) > $null
                }
            }
        }

        end
        {
            return $filterArtifacts
        }
    }

    Add-Type -AssemblyName ('Microsoft.BizTalk.ExplorerOM, Version=3.0.1.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35, processorArchitecture=MSIL')

    $exitCode = 0

    [System.Environment]::NewLine + "   [{0}] Remote artifacts {1} started..." -f $server.Hostname, (IIf $enableArtifacts "enabling" "disabling") | Write-Host -ForegroundColor White
}

process
{
    if ($global:settings -eq $null)
    {
        [System.Environment]::NewLine + "   [{0}] Settings values were not relayed. Remote artifacts {1} can not continue." -f $server.Hostname, (IIf $enableArtifacts "enabling" "disabling") | Write-Host -ForegroundColor Red
        $exitCode = 1
    }
    else
    {
        $performExecution = $false
        
        $biztalkCatalog = New-Object Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer
        $biztalkCatalog.ConnectionString = Get-BizTalkConnectionString $server

        # Only bring artifacts that are not already in the correct status for processing
        $statusArtifacts = !($enableArtifacts)

        # Get BizTalk artifacts according to processing settings
        #$receiveLocations = IIf $artifacts.ReceiveLocations { Filter-Artifacts (Get-ReceiveLocations $biztalkCatalog) $_ $statusArtifacts } { New-Object System.Collections.ArrayList }
        #$sendPorts = IIf $artifacts.SendPorts { Filter-Artifacts (Get-SendPorts $biztalkCatalog) $_ $statusArtifacts } { New-Object System.Collections.ArrayList }
        #$orchestrations = IIf $artifacts.Orchestrations { Filter-Artifacts (Get-Orchestrations $biztalkCatalog) $_ $statusArtifacts } { New-Object System.Collections.ArrayList }
        #$applications = IIf $artifacts.Applications { Filter-Artifacts (Get-Applications $biztalkCatalog) $_ $statusArtifacts } { New-Object System.Collections.ArrayList }

        #$receiveLocationsCount = IIf $receiveLocations { $_.Count } 0
        #$sendPortsCount = IIf $sendPorts { $_.Count } 0
        #$orchestrationsCount = IIf $orchestrations { $_.Count } 0
        #$applicationsCount = IIf $applications { $_.Count } 0

        # Assumes zero artifacts to be changed
        $receiveLocationsCount = 0
        $sendPortsCount = 0
        $orchestrationsCount = 0
        $applicationsCount = 0

        # Create empty lists for artifacts to be processed.
        $receiveLocations = New-Object System.Collections.ArrayList
        $sendPorts = New-Object System.Collections.ArrayList
        $orchestrations = New-Object System.Collections.ArrayList
        $applications = New-Object System.Collections.ArrayList

        # Get Receive Locations artifacts according to processing settings
        if ($artifacts.ReceiveLocations -ne $null) {
            Filter-Artifacts (Get-ReceiveLocations $biztalkCatalog) $artifacts.ReceiveLocations $statusArtifacts | % {
                $receiveLocations.Add($_) > $null
            }
            $receiveLocationsCount = $receiveLocations.Count
        }

        # Get Send Ports artifacts according to processing settings
        if ($artifacts.SendPorts -ne $null) {
            Filter-Artifacts (Get-SendPorts $biztalkCatalog) $artifacts.SendPorts $statusArtifacts | % {
                $sendPorts.Add($_) > $null
            }
            $sendPortsCount = $sendPorts.Count
        }

        # Get Orchestrations artifacts according to processing settings
        if ($artifacts.Orchestrations -ne $null) {
            Filter-Artifacts (Get-Orchestrations $biztalkCatalog) $artifacts.Orchestrations $statusArtifacts | % {
                $orchestrations.Add($_) > $null
            }
            $orchestrationsCount = $orchestrations.Count
        }
        
        # Get Applications artifacts according to processing settings
        if ($artifacts.Applications -ne $null) {
            Filter-Artifacts (Get-Applications $biztalkCatalog) $artifacts.Applications $statusArtifacts | % {
                $applications.Add($_) > $null
            }
            $applicationsCount = $applications.Count
        }

        if (($receiveLocationsCount + $sendPortsCount + $orchestrationsCount + $applicationsCount) -eq 0)
        {
            [System.Environment]::NewLine + "   [{0}] Found no artifacts to be {1}." -f $server.Hostname, (IIf $enableArtifacts "enabled" "disabled") | Write-Host -ForegroundColor Yellow
        }
        else
        {
            [System.Environment]::NewLine + "   [{0}] Found the following artifacts to be {1}:" -f $server.Hostname, (IIf $enableArtifacts "enabled" "disabled") | Write-Host -ForegroundColor Cyan

            # Display all artifacts to be changed
            $receiveLocations | % { 
                "   [{0}]    > [ReceiveLocation] {1} (Application: {2})" -f $server.Hostname, $_.Name, $_.Application | Write-Host -ForegroundColor Cyan
            }
            $sendPorts | % { 
                "   [{0}]    > [SendPort] {1} (Application: {2})" -f $server.Hostname, $_.Name, $_.Application | Write-Host -ForegroundColor Cyan 
            }
            $orchestrations | % { 
                "   [{0}]    > [Orchestration] {1} (Application: {2})" -f $server.Hostname, $_.Name, $_.Application | Write-Host -ForegroundColor Cyan 
            }
            $applications | % { 
                "   [{0}]    > [Application] {1}" -f $server.Hostname, $_.Name | Write-Host -ForegroundColor Cyan 
            }

            if (!$global:settings.SwitchAutomatic)
            {
                $performExecution = Ask-UserAcceptance ("   [{0}] Proceed with the artifacts {1}?" -f $server.Hostname, (IIf $enableArtifacts "enabling" "disabling")) 0
            }
            else
            {
                $performExecution = $true
            }
        }
        
        # If user accepted, changes all artifacts found.
        if ($performExecution)
        {
            if (!$global:settings.SwitchMock)
            {
                [System.Environment]::NewLine + "   [{0}] The following artifacts were {1}:" -f $server.Hostname, (IIf $enableArtifacts "enabled" "disabled") | Write-Host -ForegroundColor Green

                # Changes the status of artifacts
                $receiveLocations | % { $_.Artifact.Enable = $enableArtifacts }
                $sendPorts | % { $_.Artifact.Status = IIf $enableArtifacts ([Microsoft.BizTalk.ExplorerOM.PortStatus]::Started) ([Microsoft.BizTalk.ExplorerOM.PortStatus]::Stopped) }
                $orchestrations | % { $_.Artifact.Status = IIf $enableArtifacts ([Microsoft.BizTalk.ExplorerOM.OrchestrationStatus]::Started) ([Microsoft.BizTalk.ExplorerOM.OrchestrationStatus]::Enlisted) }
                $applications | % { 
                    if ($enableArtifacts) {
                        $_.Artifact.Start(([Microsoft.BizTalk.ExplorerOM.ApplicationStartOption]::StartAll))
                    } else {
                        $_.Artifact.Stop(([Microsoft.BizTalk.ExplorerOM.ApplicationStopOption]::StopAll))
                    }
                }
            
                # Commit changes
                $biztalkCatalog.SaveChanges()

                # Display all artifacts changed
                $receiveLocations | % {
                    "   [{0}]    > [ReceiveLocation] {1}: {2}" -f $server.Hostname, $_.Name, (IIf $_.Artifact.Enable "Enabled" "Disabled") | Write-Host -ForegroundColor Green
                }
                $sendPorts | % {
                    "   [{0}]    > [SendPort] {1}: {2}" -f $server.Hostname, $_.Name, $_.Artifact.Status | Write-Host -ForegroundColor Green
                }
                $orchestrations | % {
                    "   [{0}]    > [Orchestration] {1}: {2}" -f $server.Hostname, $_.Name, $_.Artifact.Status | Write-Host -ForegroundColor Green
                }
                $applications | % {
                    "   [{0}]    > [Application] {1}: {2}" -f $server.Hostname, $_.Name, $_.Artifact.Status | Write-Host -ForegroundColor Green
                }
            }
            else
            {
                [System.Environment]::NewLine + ("   [{0}] No {1} was performed. Mock switch is on." -f $server.Hostname, (IIf $enableArtifacts "enabling" "disabling")) | Write-Host -ForegroundColor Yellow

                # Rollback any changes
                $biztalkCatalog.DiscardChanges()
            }
        }
        else
        {
            [System.Environment]::NewLine + "   [{0}] No {1} was performed." -f $server.Hostname, (IIf $enableArtifacts "enabling" "disabling") | Write-Host -ForegroundColor Yellow
            
            # Rollback any changes
            $biztalkCatalog.DiscardChanges()
        }
    }
}

end
{
    [System.Environment]::NewLine + "   [{0}] Remote artifacts {1} finished..." -f $server.Hostname, (IIf $enableArtifacts "enabling" "disabling") | Write-Host -ForegroundColor White

    return $exitCode
}
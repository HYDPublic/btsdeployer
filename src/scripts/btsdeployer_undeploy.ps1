<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Remote Undeploy Module
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Remote Undeploy Module
.NOTES
    File Name      : btsdeployer_undeploy.ps1
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
    [PSObject[]]
        $applications
)

begin
{
    function Get-ApplicationsToUndeploy
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject[]]
                $searchApplications
        )

        begin
        {
            $undeployApplications = New-Object System.Collections.ArrayList
        }

        process
        {
            foreach ($searchApplication in $searchApplications)
            {
                $searchApplicationName = $searchApplication.ApplicationName

                $undeployApplicationProjectFile = "${env:ProgramFiles(x86)}\$searchApplicationName\1.0\Deployment\$searchApplicationName.Deployment.btdfproj"
        
                if (Test-Path $undeployApplicationProjectFile)
                {
                    $projectFileItem = Get-Item $undeployApplicationProjectFile
                    
                    $undeployApplication = New-Object PSObject -Property @{

                        Name = $projectFileItem.Name
                        BaseName = $projectFileItem.BaseName
                        FullName = $projectFileItem.FullName
                    }

                    $undeployApplications.Add($undeployApplication) > $null
                }
            }
        }

        end
        {
            return $undeployApplications
        }
    }

    function Undeploy-Application
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject]
                $application,
            
            [parameter(mandatory = $true)]
            [PSObject]
                $server
        )

        process
        {
            $exitCode = 0
    
            $msbuildFile = Get-MsBuild

            $applicationName = $application.BaseName
            $applicationProjectFile = $application.FullName
    
            $deployBizTalkMgmtDB = $server.DeployBizTalkMgmtDB
            
            $deploymentTempPath = Join-Path ([System.IO.Path]::GetTempPath()) $global:settings.DeploymentID
            $deploymentTempLogPath = Join-Path $deploymentTempPath "log"

            $logFileName = Join-Path $deploymentTempLogPath ("{0}_{1}_undeploy_{2}.log" -f [DateTime]::Now.ToString("yyyy-MM-ddTHH.mm.ss.fff"), $server.Hostname, $applicationName)

            $undeployCommand = "`"$msbuildFile`""
            $undeployCommandArgs = "`"$applicationProjectFile`" /t:Undeploy /p:DeployBizTalkMgmtDB=$deployBizTalkMgmtDB /p:Configuration=Server /l:FileLogger,Microsoft.Build.Engine;logfile=`"$logFileName`""

            if ($global:settings.SwitchVerboseOutput)
            {
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $undeployCommand, $undeployCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor DarkGray
            }

            if (!$global:settings.SwitchMock)
            {
                # Undeploy application
                $exitCode = Execute-Process $undeployCommand $undeployCommandArgs
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not undeployed. Mock switch is on." -f $server.Hostname, $applicationName | Write-Host -ForegroundColor Yellow
            }

            # Check if undeploy was successful
            if($exitCode -eq 0)
            {
                [System.Environment]::NewLine + "   [{0}] {1} undeployed successfully. Exit: {2}." -f $server.Hostname, $applicationName, $exitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not undeployed successfully. Exit: {2}." -f $server.Hostname, $applicationName, $exitCode | Write-Host -ForegroundColor Red
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $undeployCommand, $undeployCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor Red
            }
    
            return $exitCode
        }
    }

    $exitCode = 0

    [System.Environment]::NewLine + "   [{0}] Undeploy started..." -f $server.Hostname | Write-Host -ForegroundColor White
}

process
{
    if ($global:settings -eq $null)
    {
        [System.Environment]::NewLine + "   [{0}] Settings values were not relayed. Undeploy cannot continue." -f $server.Hostname | Write-Host -ForegroundColor Red
        $exitCode = 1
    }
    else
    {
        $performUndeploy = $false

        $undeployApplications = Get-ApplicationsToUndeploy $applications
        $undeployApplicationsMeasure = $undeployApplications | Measure-Object

        if ($undeployApplicationsMeasure.Count -eq 0)
        {
            [System.Environment]::NewLine + "   [{0}] Found no similar applications to undeploy." -f $server.Hostname | Write-Host -ForegroundColor Yellow

            if (!$global:settings.SwitchForce)
            {
                $haltScript = !(Ask-UserAcceptance ("   [{0}] Proceed without undeploying?" -f $server.Hostname) 1)
            }
            else
            {
                $haltScript = $true
            }
        
            if ($haltScript -eq $true)
            {
                [System.Environment]::NewLine + "   [{0}] Scripted halted {1}." -f $server.Hostname, (IIf $global:settings.SwitchForce "automatically by -Force switch" "by user") | Write-Host -ForegroundColor Red
                throw [System.Management.Automation.RemoteException]
            }
        }
        else
        {
            [System.Environment]::NewLine + "   [{0}] Found the following similar applications deployed:" -f $server.Hostname | Write-Host -ForegroundColor Cyan
        
            foreach ($undeployApplication in $undeployApplications)
            {
                "   [{0}]    > {1}" -f $server.Hostname, $undeployApplication.FullName | Write-Host -ForegroundColor Cyan
            }
        
            if (!$global:settings.SwitchAutomatic)
            {
                $performUndeploy = Ask-UserAcceptance ("   [{0}] Proceed with the undeployment?" -f $server.Hostname) 0
            }
            else
            {
                $performUndeploy = $true
            }
        }

        # If user accepted, undeploy all similar applications found.
        if ($performUndeploy)
        {
            foreach ($undeployApplication in $undeployApplications)
            {
                $exitCode += Undeploy-Application $undeployApplication $server
            }
        }
        else
        {
            [System.Environment]::NewLine + "   [{0}] No undeploy was performed." -f $server.Hostname | Write-Host -ForegroundColor Yellow
        }
    }
}

end
{
    [System.Environment]::NewLine + "   [{0}] Undeploy finished..." -f $server.Hostname | Write-Host -ForegroundColor White

    return $exitCode
}

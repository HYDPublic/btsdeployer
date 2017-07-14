<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Remote Uninstall Module
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Remote Uninstall Module
.NOTES
    File Name      : btsdeployer_uninstall.ps1
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
    function Get-ApplicationsToUninstall
    {
        [parameter(mandatory = $true)]
        [CmdletBinding()]
        param
        (
            [PSObject[]]
                $searchApplications
        )

        begin
        {
            $uninstallApplications = New-Object System.Collections.ArrayList
        }

        process
        {
            foreach ($searchApplication in $searchApplications)
            {
                $uninstallApplication = Get-RemoteProgram -Property Uninstallstring | ? { [string]$_.ProgramName -match $searchApplication.ApplicationName }

                if ($uninstallApplication)
                {
                    $uninstallApplications.Add($uninstallApplication) > $null
                }
            }
        }

        end
        {
            return $uninstallApplications
        }
    }

    function Uninstall-Application
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
    
            $applicationProgramName = $application.ProgramName

            $uninstallStringMatch = [regex]::match($application.Uninstallstring, "(?<exec>^`"[^`"]*`"|\S*) *(?<params>.*)?")
    
            $uninstallStringExecutable = $uninstallStringMatch.Groups["exec"].Value
            $uninstallStringParameters = $uninstallStringMatch.Groups["params"].Value
            
            $deploymentTempPath = Join-Path ([System.IO.Path]::GetTempPath()) $global:settings.DeploymentID
            $deploymentTempLogPath = Join-Path $deploymentTempPath "log"

            $logFileName = Join-Path $deploymentTempLogPath ("{0}_{1}_uninstall_{2}.log" -f [DateTime]::Now.ToString("yyyy-MM-ddTHH.mm.ss.fff"), $server.Hostname, $applicationProgramName)

            $uninstallCommand = "`"$uninstallStringExecutable`""
            $uninstallCommandArgs = "$uninstallStringParameters /qn /log `"$logFileName`""

            if ($global:settings.SwitchVerboseOutput)
            {
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $uninstallCommand, $uninstallCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor DarkGray
            }

            if (!$global:settings.SwitchMock) 
            {
                # Uninstall application
                $exitCode = Execute-Process $uninstallCommand $uninstallCommandArgs
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not uninstalled. Mock switch is on." -f $server.Hostname, $applicationProgramName | Write-Host -ForegroundColor Yellow
            }

            # Check if uninstalling was successful
            if($exitCode -eq 0)
            {
                [System.Environment]::NewLine + "   [{0}] {1} uninstalled successfully. Exit: {2}." -f $server.Hostname, $applicationProgramName, $exitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not uninstalled successfully. Exit: {2}." -f $server.Hostname, $applicationProgramName, $exitCode | Write-Host -ForegroundColor Red
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $uninstallCommand, $uninstallCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor Red
            }
    
            return $exitCode
        }
    }

    $exitCode = 0

    [System.Environment]::NewLine + "   [{0}] Uninstall started..." -f $server.Hostname | Write-Host -ForegroundColor White
}

process
{
    if ($global:settings -eq $null)
    {
        [System.Environment]::NewLine + "   [{0}] Settings values were not relayed. Uninstall cannot continue." -f $server.Hostname | Write-Host -ForegroundColor Red
        $exitCode = 1
    }
    else
    {    
        $performUninstall = $false

        $uninstallApplications = Get-ApplicationsToUninstall $applications
        $uninstallApplicationsMeasure = $uninstallApplications | Measure-Object

        if ($uninstallApplicationsMeasure.Count -eq 0)
        {
            [System.Environment]::NewLine + "   [{0}] Found no similar applications to uninstall." -f $server.Hostname | Write-Host -ForegroundColor Yellow
        
            if (!$global:settings.SwitchForce)
            {
                $haltScript = !(Ask-UserAcceptance ("   [{0}] Proceed without uninstalling?" -f $server.Hostname) 1)
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
            [System.Environment]::NewLine + "   [{0}] Found the following similar applications installed:" -f $server.Hostname | Write-Host -ForegroundColor Cyan
        
            foreach ($uninstallApplication in $uninstallApplications)
            {
                "   [{0}]    > {1} : {2}" -f $server.Hostname, $uninstallApplication.ProgramName, $uninstallApplication.Uninstallstring | Write-Host -ForegroundColor Cyan
            }

            if (!$global:settings.SwitchAutomatic)
            {
                $performUninstall = Ask-UserAcceptance ("   [{0}] Proceed with the uninstall?" -f $server.Hostname) 0
            }
            else
            {
                $performUninstall = $true
            }
        }

        # If user accepted, uninstall all similar applications found.
        if ($performUninstall)
        {
            foreach ($uninstallApplication in $uninstallApplications)
            {
                $exitCode += Uninstall-Application $uninstallApplication $server
            }
        }
        else
        {
            [System.Environment]::NewLine + "   [{0}] No uninstall was performed." -f $server.Hostname | Write-Host -ForegroundColor Yellow
        }
    }
}

end
{
    [System.Environment]::NewLine + "   [{0}] Uninstall finished..." -f $server.Hostname | Write-Host -ForegroundColor White

    return $exitCode
}

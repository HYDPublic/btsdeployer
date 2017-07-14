<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Remote Prerequisite Verification Module
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Remote Prerequisite Verification Module
.NOTES
    File Name      : btsdeployer_prerequisites.ps1
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
    function Create-TempDirectories
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
            $exitCode = 0

            $deploymentTempPath = Join-Path ([System.IO.Path]::GetTempPath()) $global:settings.DeploymentID

            $deploymentTempMsiPath = Join-Path $deploymentTempPath "msi"
            $deploymentTempLogPath = Join-Path $deploymentTempPath "log"

            New-Item -Path $deploymentTempMsiPath -ItemType Directory -Force > $null
            New-Item -Path $deploymentTempLogPath -ItemType Directory -Force > $null

            if (Test-Path $deploymentTempMsiPath)
            {
                [System.Environment]::NewLine + "   [{0}] Check for {1}: OK." -f $server.Hostname, $deploymentTempMsiPath | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] Check for {1}: Failed. Directoy not found." -f $server.Hostname, $deploymentTempMsiPath | Write-Host -ForegroundColor Red
                $exitCode++
            }

            if (Test-Path $deploymentTempLogPath)
            {
                [System.Environment]::NewLine + "   [{0}] Check for {1}: OK." -f $server.Hostname, $deploymentTempLogPath | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] Check for {1}: Failed. Directoy not found." -f $server.Hostname, $deploymentTempLogPath | Write-Host -ForegroundColor Red
                $exitCode++
            }

            return $exitCode
        }
    }

    function Check-Instances
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
    
            $biztalkOperations = New-Object Microsoft.BizTalk.Operations.BizTalkOperations

            $serviceInstances = $biztalkOperations.GetServiceInstances() | ? { $_.Application -eq $application.ApplicationName } | Sort-Object -Property "InstanceStatus"

            if ($serviceInstances.Count -gt 0)
            {
                [System.Environment]::NewLine + "   [{0}] Active instances found for {1} application:" -f $server.Hostname, $application.ApplicationName | Write-Host -ForegroundColor Red
        
                foreach ($serviceInstance in $serviceInstances)
                {
                    "   [{0}]    > {1} : {2}" -f $server.Hostname, $serviceInstance.InstanceStatus, $serviceInstance.ServiceType | Write-Host -ForegroundColor Red

                    $exitCode++
                }
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] No active instances were found for {1} application." -f $server.Hostname, $application.ApplicationName | Write-Host -ForegroundColor Green
            }

            return $exitCode
        }
    }

    function Check-PowerShellVersion
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
            $exitCode = 0
    
            if ($PSVersionTable.PSVersion -ne $null)
            {
                if ($PSVersionTable.PSVersion.Major -ge 3)
                { 
                    [System.Environment]::NewLine + "   [{0}] Check for PowerShell Verson: OK. Version {1} found." -f $server.Hostname, $PSVersionTable.PSVersion | Write-Host -ForegroundColor Green
                }
                else
                {
                    [System.Environment]::NewLine + "   [{0}] Check for PowerShell Version Failed. Version {1} found." -f $server.Hostname, $PSVersionTable.PSVersion | Write-Host -ForegroundColor Red
                    $exitCode++
                }
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] Check for PowerShell Version Failed. Version 1.0 found." -f $server.Hostname | Write-Host -ForegroundColor Red
                $exitCode++
            }

            return $exitCode
        }
    }

    Add-Type -AssemblyName ('Microsoft.BizTalk.Operations, Version=3.0.1.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35, processorArchitecture=MSIL')

    $exitCode = 0

    [System.Environment]::NewLine + "   [{0}] Remote prerequisites check started..." -f $server.Hostname | Write-Host -ForegroundColor White
}

process
{
    if ($global:settings -eq $null)
    {
        [System.Environment]::NewLine + "   [{0}] Settings values were not relayed. Remote prerequisites check can not continue." -f $server.Hostname | Write-Host -ForegroundColor Red
        $exitCode = 1
    }
    else
    {
        $exitCode += Create-TempDirectories $server

        $exitCode += Check-PowerShellVersion $server
        
        foreach ($application in $applications)
        {
            $exitCode += Check-Instances $application $server
        }
    }
}

end
{
    [System.Environment]::NewLine + "   [{0}] Remote prerequisites check finished..." -f $server.Hostname | Write-Host -ForegroundColor White

    return $exitCode
}

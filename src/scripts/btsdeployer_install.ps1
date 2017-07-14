<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Remote Install Module
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Remote Install Module
.NOTES
    File Name      : btsdeployer_install.ps1
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
    function Install-Application
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
            
            $applicationName = $application.ApplicationName
            
            $deploymentTempPath = Join-Path ([System.IO.Path]::GetTempPath()) $global:settings.DeploymentID
            $deploymentTempMsiPath = Join-Path $deploymentTempPath "msi"
            $deploymentTempLogPath = Join-Path $deploymentTempPath "log"

            $applicationInstaller = Join-Path $deploymentTempMsiPath ("{0}" -f $application.Name)

            $logFileName = Join-Path $deploymentTempLogPath ("{0}_{1}_install_{2}.log" -f [DateTime]::Now.ToString("yyyy-MM-ddTHH.mm.ss.fff"), $server.Hostname, $applicationName)

            $installCommand = "MsiExec.exe"
            $installCommandArgs = "/i `"$applicationInstaller`" /passive /log `"$logFileName`" INSTALLDIR=`"${env:ProgramFiles(x86)}\$applicationName\1.0\`""

            if ($global:settings.SwitchVerboseOutput)
            {
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $installCommand, $installCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor DarkGray
            }

            if (!$global:settings.SwitchMock)
            {
                # Install application
                $exitCode = Execute-Process $installCommand $installCommandArgs
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not installed. Mock switch is on." -f $server.Hostname, $applicationName | Write-Host -ForegroundColor Yellow
            }

            # Check if installation was successful
            if($exitCode -eq 0)
            {
                [System.Environment]::NewLine + "   [{0}] {1} installed successfully. Exit: {2}." -f $server.Hostname, $applicationName, $exitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not installed successfully. Exit: {2}." -f $server.Hostname, $applicationName, $exitCode | Write-Host -ForegroundColor Red
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $installCommand, $installCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor Red
            }
    
            return $exitCode
        }
    }

    $exitCode = 0

    [System.Environment]::NewLine + "   [{0}] Install started..." -f $server.Hostname | Write-Host -ForegroundColor White
}

process
{
    if ($global:settings -eq $null)
    {
        [System.Environment]::NewLine + "   [{0}] Settings values were not relayed. Install cannot continue." -f $server.Hostname | Write-Host -ForegroundColor Red
        $exitCode = 1
    }
    else
    {
        if (!$global:settings.SwitchAutomatic)
        {
            $performInstall = Ask-UserAcceptance ("   [{0}] Proceed with the installation?" -f $server.Hostname) 0
        }
        else
        {
            $performInstall = $true
        }

        # If user accepted, install all applications.
        if ($performInstall)
        {
            foreach ($application in $applications)
            {
                $exitCode += Install-Application $application $server
            }
        }
        else
        {
            [System.Environment]::NewLine + "   [{0}] No install was performed." -f $server.Hostname | Write-Host -ForegroundColor Yellow
        }
    }
}

end
{
    [System.Environment]::NewLine + "   [{0}] Install finished..." -f $server.Hostname | Write-Host -ForegroundColor White

    return $exitCode
}

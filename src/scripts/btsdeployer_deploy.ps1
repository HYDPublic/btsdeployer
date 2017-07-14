<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Remote Deploy Module
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Remote Deploy Module
.NOTES
    File Name      : btsdeployer_deploy.ps1
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
    function Deploy-Application
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

            $deployBizTalkMgmtDB = $server.DeployBizTalkMgmtDB

            $applicationName = $application.ApplicationName
            $applicationPath = "${env:ProgramFiles(x86)}\$applicationName\1.0\Deployment"

            $applicationProjectFileName = "{0}.Deployment.btdfproj" -f $applicationName
            $applicationProjectFile = Join-Path $applicationPath $applicationProjectFileName
                 
            $applicationEnvironmentFileName = "Exported_{0}Settings.xml" -f $global:settings.Environment
            $applicationEnvironmentFile = Join-Path "$applicationPath\EnvironmentSettings" $applicationEnvironmentFileName
                 
            $applicationNodeFileName = "Node{0}Settings.xml" -f $server.Node
            $applicationNodeFile = Join-Path "$applicationPath\NodeConfig" $applicationNodeFileName
            
            $deploymentTempPath = Join-Path ([System.IO.Path]::GetTempPath()) $global:settings.DeploymentID
            $deploymentTempLogPath = Join-Path $deploymentTempPath "log"

            $logFileName = Join-Path $deploymentTempLogPath ("{0}_{1}_deploy_{2}.log" -f [DateTime]::Now.ToString("yyyy-MM-ddTHH.mm.ss.fff"), $server.Hostname, $applicationName)

            $deployCommand = "`"$msbuildFile`""
            $deployCommandArgs = "`"$applicationProjectFile`" /t:Deploy /p:DeployBizTalkMgmtDB=$deployBizTalkMgmtDB;Configuration=Server;SkipUndeploy=true;ENV_SETTINGS=`"$applicationEnvironmentFile`";NODE_SETTINGS=`"$applicationNodeFile`" /l:FileLogger,Microsoft.Build.Engine;logfile=`"$logFileName`""

            if ($global:settings.SwitchVerboseOutput)
            {
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $deployCommand, $deployCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor DarkGray
            }

            if (!$global:settings.SwitchMock)
            {
                # Deploy application
                $exitCode = Execute-Process $deployCommand $deployCommandArgs
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not deployed. Mock switch is on." -f $server.Hostname, $applicationName | Write-Host -ForegroundColor Yellow
            }

            # Check if deploy was successful
            if($exitCode -eq 0)
            {
                [System.Environment]::NewLine + "   [{0}] {1} deployed successfully. Exit: {2}." -f $server.Hostname, $applicationName, $exitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "   [{0}] {1} not deployed successfully. Exit: {2}." -f $server.Hostname, $applicationName, $exitCode | Write-Host -ForegroundColor Red
                [System.Environment]::NewLine + "   [{0}] Command: {1}{3}   [{0}] Args: {2}" -f $server.Hostname, $deployCommand, $deployCommandArgs, [System.Environment]::NewLine | Write-Host -ForegroundColor Red
            }

            return $exitCode
        }
    }

    $exitCode = 0

    [System.Environment]::NewLine + "   [{0}] Deploy started..." -f $server.Hostname | Write-Host -ForegroundColor White
}

process
{
    if ($global:settings -eq $null)
    {
        [System.Environment]::NewLine + "   [{0}] Settings values were not relayed. Deploy cannot continue." -f $server.Hostname | Write-Host -ForegroundColor Red
        $exitCode = 1
    }
    else
    {
        if (!$global:settings.SwitchAutomatic)
        {
            $performDeploy = Ask-UserAcceptance ("   [{0}] Proceed with the deploy?" -f $server.Hostname) 0
        }
        else
        {
            $performDeploy = $true
        }

        # If user accepted, deploy all applications.
        if ($performDeploy)
        {
            foreach ($application in $applications)
            {
                $exitCode += Deploy-Application $application $server
            }
        }
        else
        {
            [System.Environment]::NewLine + "   [{0}] No deploy was performed." -f $server.Hostname | Write-Host -ForegroundColor Yellow
        }
    }
}

end
{
    [System.Environment]::NewLine + "   [{0}] Deploy finished..." -f $server.Hostname | Write-Host -ForegroundColor White

    return $exitCode
}

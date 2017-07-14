<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Main script
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Main script
.NOTES
    File Name          : btsdeployer_main.ps1
    Author             : Willians Schallemberger Schneider, @schalleneider
    Prerequisite       : PowerShell v3
                         CredSSP authentication client mode activated on BizTalk Server
                         Allow Delegating Fresh Credentials Group Policy Enabled for *.domain.com on BizTalk Server
                         CredSSP authentication server mode activated on SQL Server Server
                         WinRM must be active and configured on BizTalk Server
.PARAMETERS
    EnvironmentSettings : Mandatory. Absolute or relative address of an valid environment configuration file.
    ArtifactsSettings   : Absolute or relative address of an valid BizTalk artifacts configuration file.
    OutTranscript       : Transcript file with the console output contents.
    ApplicationSource   : Local directory containing the msi packages to be installed.
    LogRepository       : Local directory where the installation logs will be stored.
    UserName            : Username to be used for impersonation. Domain\User format. If not provided, an valid user/password will be prompted.
    Password            : Password to be used for impersonation. Should be already converted to its SecureString encrypted representation. If not provided, an valid user/password will be prompted.
                          To generate an SecureString encrypted password, execute: 
                          > Read-Host -AsSecureString | ConvertFrom-SecureString | Out-File C:\OUTPUT.txt
    Mock                : Turns on/off the execution of the commands. Used to test script without performing an real installation.
    Automatic           : Turns on/off the automatic execution of the script, without asking for user confirmation before executing the commands.
    Force               : Turns on/off the all user confirmations. The script will assume in all scenarios the default behaviour.
    VerboseOutput       : Turns on/off the output of settings, commands arguments and remote output.
.USAGE
    > Step-by-step execution.
    > Confirmation will be requested for all changes.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini"
    
    > Step-by-step execution.
    > Confirmation will be requested for all changes.
    > Configured artifacts will be pre/post-processed.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -ArtifactsSettings "btsdeployer_artifacts_#.ini"

    > Step-by-step execution.
    > Confirmation will be requested for all changes.
    > Console output will be transcripted to an .log file. 
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -OutTranscript ".\log\btsdeployer_console.log"

    > Step-by-step execution.
    > All commands and remote output will be displayed.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -VerboseOutput
    
    > Step-by-step execution.
    > All commands and remote output will be displayed.
    > Credentials will be prompted for the informed username.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -UserName "UAPINC\username"

    > Step-by-step execution.
    > All commands and remote output will be displayed.
    > No credentials will be prompted.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -UserName "UAPINC\username" -Password "#"
    
    > Mock execution.
    > No real changes are performed in the environment.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -Mock

    > Automatic execution. 
    > Script will proceed automatically for all expected behaviours and user confirmation will be prompted for unexpected behaviours.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -Automatic

    > Forced execution. 
    > Script will choose automatically the default actions for all behaviours.
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -Force

    > Alternative directoy for installation packages
    > Script will obtain the installations packages from the specified directory. Otherwise, ".\msi" directory will be used. 
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -ApplicationSource "c:\btsdeployer\msi"

    > Alternative directory for log files
    > Script will store the log files at the specified directory. Otherwise, ".\log" directory will be used. 
    .\scripts\btsdeployer_main.ps1 -EnvironmentSettings "btsdeployer_settings_#.ini" -LogRepository "c:\btsdeployer\log"

.TODO
    // Nothing to see here. Yoohay!! :)
#>

[CmdletBinding()]
param
(
    [parameter(mandatory = $true)]
    [string]
        $EnvironmentSettings,

    [string]
        $ArtifactsSettings,

    [string]
        $OutTranscript,

    [string]
        $ApplicationSource,

    [string]
        $LogRepository,

    [string]
        $UserName,

    [string]
        $Password,

    [switch]
        $Mock,

    [switch]
        $Automatic,
        
    [switch]
        $Force,

    [switch]
        $VerboseOutput
)

begin
{
    # Functions

    function Get-Settings
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [string]
                $configurationFile
        )

        process
        {
            try
            {
                return Get-Content -Raw -Path $configurationFile | ConvertFrom-Json
            }
            catch
            {
                $_.Exception | Format-List -Force | Write-Error
                Terminate-Script "There is an error in the settings file. Please check the file contents and try again. The settings file should be written in JSON format."
            }
        }
    }

    function Get-LocalApplicationsToProcess
    {
        [CmdletBinding()]
        param()

        begin
        {
            $applications = New-Object System.Collections.ArrayList
        }

        process
        {
            if (Test-Path -Path $global:settings.LocalApplicationSource)
            {
                $installerFiles = Get-ChildItem -LiteralPath $global:settings.LocalApplicationSource -Filter *.msi

                $installerFiles | % {
                    $application = New-Object PSObject -Property @{
                        Name = $_.Name
                        ApplicationName = $_.Name.Split("-")[0]
                        OriginalPath = $_.FullName
                    }
                    $applications.Add($application) > $null
                }
            }
            else
            {
                [System.Environment]::NewLine + "The specified local path does not exist: {0}." -f $global:settings.LocalApplicationSource | Write-Host -ForegroundColor Red
            }
        }

        end
        {
            return $applications
        }
    }

    function Copy-LocalApplicationsToServers
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject[]]
                $servers,
            
            [parameter(mandatory = $true)]
            [PSObject[]]
                $applications
        )

        begin
        {
            $exitCode = 0

            [System.Environment]::NewLine + "Copying local installers into servers." | Write-Host -ForegroundColor White
        }

        process
        {
            foreach ($server in $servers)
            {
                try
                {
                    $remoteTempPath = Invoke-Command -ComputerName $server.Hostname -Authentication "CredSSP" -Credential $global:credential -ScriptBlock { [System.IO.Path]::GetTempPath() }
                    $remoteDeploymentTempPath = Join-Path $remoteTempPath $global:settings.DeploymentID
                    $remoteDeploymentTempMsiPath = Join-Path $remoteDeploymentTempPath "msi"
                    $remoteDeploymentTempMsiUNCPath = $remoteDeploymentTempMsiPath -replace '^(.):', ("\\{0}\`$1$" -f $server.Hostname)

                    $tempDrive = New-PSDrive -Name (Get-NextFreeDriveLetter) -Root $remoteDeploymentTempMsiUNCPath -Credential $global:credential -Persist -PSProvider FileSystem

                    $msiRemotePath = "{0}:\" -f $tempDrive.Name

                    foreach ($application in $applications)
                    {
                        Start-BitsTransfer -Source $application.OriginalPath -Destination $msiRemotePath -Credential $global:credential

                        "   [{0}] {1} transfered." -f $server.Hostname, $application.Name | Write-Host -ForegroundColor Green
                    }

                    Remove-PSDrive -Name $tempDrive.Name
                }
                catch
                {
                    $_.Exception | Format-List -Force | Write-Error
                    $exitCode++
                }
            }
        }

        end
        {
            return $exitCode
        }
    }
    
    function Test-Remote
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject[]]
                $servers
        )

        begin
        {
            $exitCode = 0

            [System.Environment]::NewLine + "Testing remote session connection into servers." -f $server.Hostname | Write-Host -ForegroundColor White
        }

        process
        {
            foreach ($server in $servers)
            {
                $remoteSession = New-PSSession -ComputerName $server.Hostname -Authentication "CredSSP" -Credential $global:credential

                if ($remoteSession)
                {
                    "   [{0}] Remote session opened." -f $server.Hostname | Write-host -ForegroundColor Green
                    
                    Remove-PSSession -Session $remoteSession
                }
                else
                {
                    $exitCode++
                }
            }
        }

        end
        {
            return $exitCode
        }
    }

    function Invoke-Remote
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [string]
                $mainScript,

            [parameter(mandatory = $true)]
            [string[]]
                $includeScripts,

            [parameter(mandatory = $true)]
            [PSObject[]]
                $servers,
            
            [parameter(mandatory = $true)]
            [object[]]
                $arguments
        )

        begin
        {
            $exitCode = 0
        }

        process
        {
            foreach ($server in $servers)
            {
                $remoteSession = New-PSSession -ComputerName $server.Hostname -Authentication "CredSSP" -Credential $global:credential
                
                if ($remoteSession)
                {
                    # Create argument list with server and settings objects 
                    $argumentsArray = New-Object System.Collections.ArrayList
                    
                    $argumentsArray.Add($server) > $null
                    $argumentsArray.Add($global:settings) > $null
                    $argumentsArray.AddRange($arguments) > $null
                    
                    foreach ($includeScript in $includeScripts)
                    {
                        Invoke-Command -Session $remoteSession -FilePath $includeScript
                    }

                    $exitCode += Invoke-Command -Session $remoteSession -FilePath $mainScript -ArgumentList $argumentsArray
    
                    Remove-PSSession -Session $remoteSession
                }
                else
                {
                    $exitCode++
                }
            }
        }

        end
        {
            return $exitCode
        }
    }

    function Ask-ChangeBehaviorOrTerminate
    {
        [CmdletBinding()]
        param
        ()

        process
        {
            if (!$global:settings.SwitchForce)
            {
                if ((Ask-UserAcceptance "Errors occured during previous steps. Proceed with the script execution?" 1))
                {
                    # If error occured while in automatic mode, change the behavior.
                    if (!$global:settings.SwitchAutomatic)
                    {
                        $global:settings.SwitchAutomatic = $true
                    }
                }
                else
                {
                    Terminate-Script "Scripted halted by user."
                }
            }
            else
            {
                Terminate-Script "Scripted halted automatically by -Force switch."
            }
        }
    }

    function Get-NextFreeDriveLetter
    {
        [CmdletBinding()]
        param
        ()

        process
        {
            $mappedDrives = New-Object System.Collections.ArrayList

            $mappedDrives.AddRange(@(
                [System.IO.DriveInfo]::GetDrives() | % { 
                    ($_.Name)[0]
                }
            )) > $null
        
            if ($mappedDrives.Count -ne 0)
            {
                return [char[]](68..90) | ? { 
                    $mappedDrives -notcontains $_ 
                } | Select-Object -Last 1
            }
            else
            {
                Terminate-Script "No free drive was found for temporary mapping. Please ensure that the system has at least one drive available and try again."
            }
        }
    }

    function Get-LogFilesFromServers
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject[]]
                $servers
        )

        begin
        {
            $exitCode = 0

            [System.Environment]::NewLine + "Getting log files from servers." | Write-Host -ForegroundColor White
        }

        process
        {
            foreach ($server in $servers)
            {
                try
                {
                    $remoteTempPath = Invoke-Command -ComputerName $server.Hostname -Authentication "CredSSP" -Credential $global:credential -ScriptBlock { [System.IO.Path]::GetTempPath() }
                    $remoteDeploymentTempPath = Join-Path $remoteTempPath $global:settings.DeploymentID
                    $remoteDeploymentTempLogPath = Join-Path $remoteDeploymentTempPath "log"
                    $remoteDeploymentTempLogUNCPath = $remoteDeploymentTempLogPath -replace '^(.):', ("\\{0}\`$1$" -f $server.Hostname)

                    $tempDrive = New-PSDrive -Name (Get-NextFreeDriveLetter) -Root $remoteDeploymentTempLogUNCPath -Credential $global:credential -Persist -PSProvider FileSystem

                    $logRemotePath = "{0}:\" -f $tempDrive.Name
                    $logRemotePathFilter = "{0}\*.log" -f $logRemotePath
                    
                    $logFilesCount = (Get-ChildItem $logRemotePathFilter | Measure-Object).Count

                    Start-BitsTransfer -Source $logRemotePathFilter -Destination $global:settings.LocalLogRepository -Credential $global:credential -TransferType Download

                    Remove-PSDrive -Name $tempDrive.Name

                    "   [{0}] {1} Log files copied." -f $server.Hostname, $logFilesCount | Write-Host -ForegroundColor Green
                }
                catch
                {
                    $_.Exception | Format-List -Force | Write-Error
                    $exitCode++
                }
            }
        }

        end
        {
            return $exitCode
        }
    }

    function CleanUp-Servers
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject[]]
                $servers
        )

        begin
        {
            $exitCode = 0

            [System.Environment]::NewLine + "Cleaning up files from servers." | Write-Host -ForegroundColor White
        }

        process
        {
            foreach ($server in $servers)
            {
                try
                {
                    Invoke-Command -ComputerName $server.Hostname -Authentication "CredSSP" -Credential $global:credential -ScriptBlock { param($deploymentID) Remove-Item -Recurse -Force (Join-Path ([System.IO.Path]::GetTempPath()) $deploymentID) } -ArgumentList $global:settings.DeploymentID

                    "   [{0}] Cleaned." -f $server.Hostname | Write-Host -ForegroundColor Green
                }
                catch
                {
                    $_.Exception | Format-List -Force | Write-Error
                    $exitCode++
                }
            }
        }

        end
        {
            return $exitCode
        }
    }

    function Check-Prerequisites
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject[]]
                $applications,
            
            [parameter(mandatory = $true)]
            [PSObject[]]
                $servers
        )

        begin
        {
            $exitCode = 0

            [System.Environment]::NewLine + "Checking prerequisites for script execution." | Write-Host -ForegroundColor White
        }

        process
        {
            # Check for local log path.
            if (Test-Path $global:settings.LocalLogRepository)
            {
                [System.Environment]::NewLine + "Check for {0}: OK." -f $global:settings.LocalLogRepository | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "Check for {0}: Failed. Directoy not found." -f $global:settings.LocalLogRepository | Write-Host -ForegroundColor Red
                $exitCode++
            }
            
            # Test remote session connection
            $testRemoteExitCode = Test-Remote $servers
            $exitCode += $testRemoteExitCode

            # Execute Remote procedures only if there was no errors
            if ($exitCode -eq 0)
            {
                # Pre-Processing artifacts to enable
                if ($global:preProcessingArtifactsEnable -ne $null)
                {
                    $preProcessArtifactsEnableExitCode = Process-Artifacts $global:preProcessingArtifactsEnable $servers $true
                
                    if ($preProcessArtifactsEnableExitCode -eq 0)
                    {
                        [System.Environment]::NewLine + "Pre-processing artifacts to enable ended without errors. Exit: {0}." -f $preProcessArtifactsEnableExitCode | Write-Host -ForegroundColor Green
                    }
                    else
                    {
                        [System.Environment]::NewLine + "Some errors occured while pre-processing artifacts to enable. Please check the error messages and try again. Exit: {0}." -f $preProcessArtifactsEnableExitCode | Write-Host -ForegroundColor Red
                        Ask-ChangeBehaviorOrTerminate
                    }
                
                    $exitCode += $preProcessArtifactsEnableExitCode
                }
                else
                {
                    [System.Environment]::NewLine + "Artifacts to enable will not be pre-processed. Respective configuration group is not present in the artifacts settings file." | Write-Host -ForegroundColor Yellow
                }

                # Pre-Processing artifacts to disable
                if ($global:preProcessingArtifactsDisable -ne $null)
                {
                    $preProcessArtifactsDisableExitCode  = Process-Artifacts $global:preProcessingArtifactsDisable $servers $false

                    if ($preProcessArtifactsDisableExitCode -eq 0)
                    {
                        [System.Environment]::NewLine + "Pre-processing artifacts to disable ended without errors. Exit: {0}." -f $preProcessArtifactsDisableExitCode | Write-Host -ForegroundColor Green
                    }
                    else
                    {
                        [System.Environment]::NewLine + "Some errors occured while pre-processing artifacts to disable. Please check the error messages and try again. Exit: {0}." -f $preProcessArtifactsDisableExitCode | Write-Host -ForegroundColor Red
                        Ask-ChangeBehaviorOrTerminate
                    }

                    $exitCode += $preProcessArtifactsDisableExitCode
                }
                else
                {
                    [System.Environment]::NewLine + "Artifacts to disable will not be pre-processed. Respective configuration group is not present in the artifacts settings file." | Write-Host -ForegroundColor Yellow
                }

                # Test remote prerequisites
                $exitCode += Invoke-Remote ("{0}\btsdeployer_prerequisites.ps1" -f $global:rootPath) @( "{0}\btsdeployer_helper.ps1" -f $global:rootPath ) $servers @( ,$applications )
            }
        }
        
        end
        {
            return $exitCode
        }
    }

    function Process-Artifacts
    {
        [CmdletBinding()]
        param
        (
            [parameter(mandatory = $true)]
            [PSObject]
                $artifacts,
            
            [parameter(mandatory = $true)]
            [PSObject[]]
                $servers,

            [parameter(mandatory = $true)]
            [bool]
                $enableArtifacts
        )

        begin
        {
            $exitCode = 0

            [System.Environment]::NewLine + "{0} artifacts." -f (IIf $enableArtifacts "Enabling" "Disabling" ) | Write-Host -ForegroundColor White
        }

        process
        {
            $exitCode += Invoke-Remote ("{0}\btsdeployer_artifacts.ps1" -f $global:rootPath) @( "{0}\btsdeployer_helper.ps1" -f $global:rootPath ) $servers @( $artifacts, $enableArtifacts )
        }

        end
        {
            return $exitCode
        }
    }

    # Root path
    $global:rootPath = Split-Path $MyInvocation.MyCommand.Path

    # Import helper functions
    . ("{0}\btsdeployer_helper.ps1" -f $global:rootPath)

    # Start Transcript of console
    Start-Transcript -Path $OutTranscript
    
    # Welcome message
    [System.Environment]::NewLine + "Automatic deployment procedure for BizTalk Applications" | Write-Host -ForegroundColor White

    try
    {
        if (($username.Length -eq 0) -or ($password.Length -eq 0))
        {
            $global:credential = Get-Credential -Credential $(IIf ($username.Length -eq 0) ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) ($username))
        }
        else
        {
            $securedPassword = $password | ConvertTo-SecureString
            $global:credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($username, $securedPassword)
        }
    }
    catch
    {
        Terminate-Script ("A valid credential must be provided. Please verify the if credentials provided are correct.")
    }

    # Display the credentials provided
    [System.Environment]::NewLine + "Credentials:" | Write-Host -ForegroundColor White
    "   > {0}" -f $global:credential.UserName | Write-Host -ForegroundColor Green

    # Displays the environment settings file provided
    [System.Environment]::NewLine + "Environment Settings File:" | Write-Host -ForegroundColor White
    "   > {0}" -f $environmentSettings | Write-Host -ForegroundColor Green
    
    # Get environment settings
    $global:settings = Get-Settings $environmentSettings
    
    # Displays the artifacts settings file provided
    [System.Environment]::NewLine + "Artifacts Settings File:" | Write-Host -ForegroundColor White
    "   > {0}" -f (IIf ($artifactsSettings.Length -eq 0) "Artifacts settings file not provided. Artifacts will not be processed." $artifactsSettings) | Write-Host -ForegroundColor (IIf ($artifactsSettings.Length -eq 0) Yellow Green)

    # Get the artifacts settings
    if ($artifactsSettings.Length -ne 0)
    {
        $artifacts =  Get-Settings $artifactsSettings
    }

    $global:preProcessingArtifactsEnable = IIf $artifacts { IIf $_.PreProcessing { $_.Enable } }
    $global:preProcessingArtifactsDisable = IIf $artifacts { IIf $_.PreProcessing { $_.Disable } }
    $global:postProcessingArtifactsEnable = IIf $artifacts { IIf $_.PostProcessing { $_.Enable } }
    $global:postProcessingArtifactsDisable = IIf $artifacts { IIf $_.PostProcessing { $_.Disable } }

    # Turn on Automatic switch when Force switch is on
    if ($Force)
    {
        $Automatic = $true;
    }
    
    # Define default application source directory if parameter is not specified
    if ($ApplicationSource.Length -eq 0)
    {
        $ApplicationSource = ".\msi"
    }

    # Define default log directory if parameters is not specified
    if ($LogRepository.Length -eq 0)
    {
        $LogRepository = ".\log"
    }

    # Add switches parameters into settings
    $global:settings | Add-Member -NotePropertyName "SwitchMock" -NotePropertyValue $Mock
    $global:settings | Add-Member -NotePropertyName "SwitchAutomatic" -NotePropertyValue $Automatic
    $global:settings | Add-Member -NotePropertyName "SwitchForce" -NotePropertyValue $Force
    $global:settings | Add-Member -NotePropertyName "SwitchVerboseOutput" -NotePropertyValue $VerboseOutput

    # Add local directories into settings
    $global:settings | Add-Member -NotePropertyName "LocalApplicationSource" -NotePropertyValue $ApplicationSource
    $global:settings | Add-Member -NotePropertyName "LocalLogRepository" -NotePropertyValue $LogRepository

    # Add deployment ID into settings
    $global:settings | Add-Member -NotePropertyName "DeploymentID" -NotePropertyValue ([System.Guid]::NewGuid().ToString("N"))

    # Displays the environment configured
    [System.Environment]::NewLine + "Environment:" | Write-Host -ForegroundColor White
    "   > {0}" -f $global:settings.Environment | Write-Host -ForegroundColor Green

    # Displays the switches status
    [System.Environment]::NewLine + "Switches:" | Write-Host -ForegroundColor White
    "   > Mock: {0}" -f $global:settings.SwitchMock | Write-Host -ForegroundColor Green
    "   > Automatic: {0}" -f $global:settings.SwitchAutomatic | Write-Host -ForegroundColor Green
    "   > Force: {0}" -f $global:settings.SwitchForce | Write-Host -ForegroundColor Green
    "   > VerboseOutput: {0}" -f $global:settings.SwitchVerboseOutput | Write-Host -ForegroundColor Green

    # Displays the local directories
    [System.Environment]::NewLine + "Local Directories:" | Write-Host -ForegroundColor White
    "   > ApplicationSource: {0}" -f $global:settings.LocalApplicationSource | Write-Host -ForegroundColor Green
    "   > LogRepository: {0}" -f $global:settings.LocalLogRepository | Write-Host -ForegroundColor Green

    # Displays the deployment ID
    [System.Environment]::NewLine + "Deployment ID:" | Write-Host -ForegroundColor White
    "   > {0}" -f $global:settings.DeploymentID | Write-Host -ForegroundColor Green

    # Displays the artifacts to process if artifacts configuration file is present
    if ($artifactsSettings.Length -ne 0)
    {
        [System.Environment]::NewLine + "Artifacts To Process:" | Write-Host -ForegroundColor White

        function DisplayArtifactsToProcess ($processingArtifacts) {
            $processingArtifacts | Get-Member -Type Properties | % {
                $artifactGroupName = $_.Name
                "      > {0}:" -f $artifactGroupName | Write-Host -ForegroundColor Green
                $processingArtifacts.$artifactGroupName | % {
                    $artifactGroup = $_
                    "         >" | Write-Host -NoNewline -ForegroundColor Cyan
                    $artifactGroup | Get-Member -Type Properties | % {
                        $artifactConfigurationName = $_.Name
                        " [{0} : {1}]" -f $artifactConfigurationName, $artifactGroup.$artifactConfigurationName | Write-Host -NoNewline -ForegroundColor Cyan
                    }
                    "" | Write-Host
                }
            }
        }

        # Display pre-processing artifacts to enable configuration only if its section is present.
        if ($global:preProcessingArtifactsEnable -ne $null)
        {
            "   > Pre-Processing [Enable]:" | Write-Host -ForegroundColor White
            DisplayArtifactsToProcess $global:preProcessingArtifactsEnable
        }

        # Display pre-processing artifacts to disable configuration only if its section is present.
        if ($global:preProcessingArtifactsDisable -ne $null)
        {
            "   > Pre-Processing [Disable]:" | Write-Host -ForegroundColor White
            DisplayArtifactsToProcess $global:preProcessingArtifactsDisable
        }
        
        # Display pre-processing artifacts to enable configuration only if its section is present.
        if ($global:postProcessingArtifactsEnable -ne $null)
        {
            "   > Post-Processing [Enable]:" | Write-Host -ForegroundColor White
            DisplayArtifactsToProcess $global:postProcessingArtifactsEnable
        }
        
        # Display pre-processing artifacts to disable configuration only if its section is present.
        if ($global:postProcessingArtifactsDisable -ne $null)
        {
            "   > Post-Processing [Disable]:" | Write-Host -ForegroundColor White
            DisplayArtifactsToProcess $global:postProcessingArtifactsDisable
        }
    }

    # Get servers where application will be deployed
    $servers = $global:settings.Servers

    # Display the servers where application will be deployed
    [System.Environment]::NewLine + "Servers:" | Write-Host -ForegroundColor White
    $servers | % {
        "   > {0} - [DeployBizTalkMgmtDB : {1}] [Node : {2}]" -f $_.Hostname, $_.DeployBizTalkMgmtDB, $_.Node | Write-Host -ForegroundColor Green
    }

    # Get applications to be processed
    $applications = Get-LocalApplicationsToProcess

    if ($applications.Count -eq 0)
    {
        Terminate-Script "No applications were found for installation. Please verify the installation folder and try again."
    }

    # Displays the applications to install
    [System.Environment]::NewLine + "Applications:" | Write-Host -ForegroundColor White
    $applications | % {
        "   > {0}" -f $_.Name | Write-Host -ForegroundColor Green
    }

    # Initial confirmation before starting the script. Disabled by -Force switch
    if (!$global:settings.SwitchForce)
    {
        $startScript = Ask-UserAcceptance "Proceed with the script execution?"
    }
    else
    {
        $startScript = $true
    }

    if (!$startScript)
    {
        Terminate-Script "Script halted by user."
    }
}

process
{
    $global:error.Clear()

    $performArtifactsRollback = $false

    # Prerequisites check
    $checkPrerequisitesExitCode = Check-Prerequisites $applications $servers
    
    # Check if prerequisites are met
    if ($checkPrerequisitesExitCode -eq 0)
    {
        [System.Environment]::NewLine + "Checking prerequisites ended without errors. Exit: {0}." -f $checkPrerequisitesExitCode | Write-Host -ForegroundColor Green

        # Copy applications installers into servers
        $copyExitCode = Copy-LocalApplicationsToServers $servers $applications

        # Check if the copy was done
        if ($copyExitCode -eq 0)
        {
            [System.Environment]::NewLine + "Installers copied successlly. Exit: {0}." -f $copyExitCode | Write-Host -ForegroundColor Green
        }
        else
        {
            $performArtifactsRollback = $true
            [System.Environment]::NewLine + "Some installers were not copied into the server. Please verify if the local specified in the configuration file exists, the credentials provided have access to it. Exit: {0}." -f $copyExitCode | Write-Host -ForegroundColor Red
        }
    }
    else
    {
        $performArtifactsRollback = $true
        [System.Environment]::NewLine + "Some prerequisites for installation were not met. Please check the messages displayed. Exit: {0}." -f $checkPrerequisitesExitCode | Write-Host -ForegroundColor Red
    }

    # If deploy cannot start, perform rollback on BizTalk artifacts and terminate script
    if ($performArtifactsRollback)
    {
        [System.Environment]::NewLine + "Rollback will be performed on pre-processed artifacts due to errors in the previous steps." | Write-Host -ForegroundColor Red
        
        # Rollback pre-processing artifacts to enable
        if ($global:preProcessingArtifactsEnable -ne $null)
        {
            $preProcessArtifactsEnableExitCode = Process-Artifacts $global:preProcessingArtifactsEnable $servers $false
        
            if ($preProcessArtifactsEnableExitCode -eq 0)
            {
                [System.Environment]::NewLine + "Rollback of pre-processing artifacts to enable ended without errors. Exit: {0}." -f $preProcessArtifactsEnableExitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "Some errors occured while rolling back pre-processing artifacts to enable. Please check the error messages and try again. Exit: {0}." -f $preProcessArtifactsEnableExitCode | Write-Host -ForegroundColor Red
            }
        }
        else
        {
            [System.Environment]::NewLine + "Rollback of pre-processed artifacts to enable will not be performed. Respective configuration group is not present in the artifacts settings file." | Write-Host -ForegroundColor Yellow
        }

        # Rollback pre-processing artifacts to disable
        if ($global:preProcessingArtifactsDisable -ne $null)
        {
            $preProcessArtifactsDisableExitCode  = Process-Artifacts $global:preProcessingArtifactsDisable $servers $true

            if ($preProcessArtifactsDisableExitCode -eq 0)
            {
                [System.Environment]::NewLine + "Rollback of pre-processing artifacts to disable ended without errors. Exit: {0}." -f $preProcessArtifactsDisableExitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "Some errors occured while rolling back pre-processing artifacts to disable. Please check the error messages and try again. Exit: {0}." -f $preProcessArtifactsDisableExitCode | Write-Host -ForegroundColor Red
            }
        }
        else
        {
            [System.Environment]::NewLine + "Rollback of pre-processed artifacts to disable will not be performed. Respective configuration group is not present in the artifacts settings file." | Write-Host -ForegroundColor Yellow
        }

        Terminate-Script "Deploy cannot start because one or more errors occured in the previous steps. Please check the error messages and try again."
    }
    
    $undeployExitCode = 1
    $uninstallExitCode = 1
    $installExitCode = 1
    $deployExitCode = 1
    
    # Undeploy / Uninstall / Install / Deploy
    try
    {
        # Remote undeploy for each server

        $undeployExitCode = Invoke-Remote ("{0}\btsdeployer_undeploy.ps1" -f $global:rootPath) @( "{0}\btsdeployer_helper.ps1" -f $global:rootPath ) $servers @( ,$applications )

        if ($undeployExitCode -eq 0)
        {
            [System.Environment]::NewLine + "Undeploy ended without errors. Exit: {0}." -f $undeployExitCode | Write-Host -ForegroundColor Green
        }
        else
        {
            [System.Environment]::NewLine + "Some errors occured during the undeploy. Please check the log files and try again. Exit: {0}." -f $undeployExitCode | Write-Host -ForegroundColor Red
            Ask-ChangeBehaviorOrTerminate
        }

        # Remote uninstall for each server

        $uninstallExitCode = Invoke-Remote ("{0}\btsdeployer_uninstall.ps1" -f $global:rootPath) @( "{0}\btsdeployer_helper.ps1" -f $global:rootPath ) $servers @( ,$applications )

        if ($uninstallExitCode -eq 0)
        {
            [System.Environment]::NewLine + "Uninstall ended without errors. Exit: {0}." -f $uninstallExitCode | Write-Host -ForegroundColor Green
        }
        else
        {
            [System.Environment]::NewLine + "Some errors occured during the uninstall. Please check the log files and try again. Exit: {0}." -f $uninstallExitCode | Write-Host -ForegroundColor Red
            Ask-ChangeBehaviorOrTerminate
        }

        # Remote install for each server

        $installExitCode = Invoke-Remote ("{0}\btsdeployer_install.ps1" -f $global:rootPath) @( "{0}\btsdeployer_helper.ps1" -f $global:rootPath ) $servers @( ,$applications )

        if ($installExitCode -eq 0)
        {
            [System.Environment]::NewLine + "Install ended without errors. Exit: {0}." -f $installExitCode | Write-Host -ForegroundColor Green
        }
        else
        {
            [System.Environment]::NewLine + "Some errors occured during the install. Please check the log files and try again. Exit: {0}." -f $installExitCode | Write-Host -ForegroundColor Red
            Ask-ChangeBehaviorOrTerminate
        }

        # Remote deploy for each server
    
        $deployExitCode = Invoke-Remote ("{0}\btsdeployer_deploy.ps1" -f $global:rootPath) @( "{0}\btsdeployer_helper.ps1" -f $global:rootPath ) $servers @( ,$applications )

        if ($deployExitCode -eq 0)
        {
            [System.Environment]::NewLine + "Deploy ended without errors. Exit: {0}." -f $deployExitCode | Write-Host -ForegroundColor Green
        }
        else
        {
            [System.Environment]::NewLine + "Some errors occured during the deploy. Please check the log files and try again. Exit: {0}." -f $deployExitCode | Write-Host -ForegroundColor Red
            Ask-ChangeBehaviorOrTerminate
        }
    }

    # Remote Error Handling
    catch [System.Management.Automation.RemoteException]
    {
        "Some errors occured remotely during the script execution. Please check the log files and try again." | Write-Error
    }

    # Clean-Up
    finally
    {
        # Post-Processing artifacts to enable
        if ($global:postProcessingArtifactsEnable -ne $null)
        {
            $postProcessArtifactsEnableExitCode = Process-Artifacts $global:postProcessingArtifactsEnable $servers $true
                
            if ($postProcessArtifactsEnableExitCode -eq 0)
            {
                [System.Environment]::NewLine + "Post-processing artifacts to enable ended without errors. Exit: {0}." -f $postProcessArtifactsEnableExitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "Some errors occured while post-processing artifacts to enable. Please check the error messages and try again. Exit: {0}." -f $postProcessArtifactsEnableExitCode | Write-Host -ForegroundColor Red
                Ask-ChangeBehaviorOrTerminate
            }
        }
        else
        {
            [System.Environment]::NewLine + "Artifacts to enable will not be post-processed. Respective configuration group is not present in the artifacts settings file." | Write-Host -ForegroundColor Yellow
        }

        # Post-Processing artifacts to disable
        if ($global:postProcessingArtifactsDisable -ne $null)
        {
            $postProcessArtifactsDisableExitCode  = Process-Artifacts $global:postProcessingArtifactsDisable $servers $false

            if ($postProcessArtifactsDisableExitCode -eq 0)
            {
                [System.Environment]::NewLine + "Post-processing artifacts to disable ended without errors. Exit: {0}." -f $postProcessArtifactsDisableExitCode | Write-Host -ForegroundColor Green
            }
            else
            {
                [System.Environment]::NewLine + "Some errors occured while post-processing artifacts to disable. Please check the error messages and try again. Exit: {0}." -f $postProcessArtifactsDisableExitCode | Write-Host -ForegroundColor Red
                Ask-ChangeBehaviorOrTerminate
            }
        }
        else
        {
            [System.Environment]::NewLine + "Artifacts to disable will not be post-processed. Respective configuration group is not present in the artifacts settings file." | Write-Host -ForegroundColor Yellow
        }

        # Get log files from servers
        $logsExitCode = Get-LogFilesFromServers $servers

        # Check if copy was done
        if ($logsExitCode  -eq 0)
        {
            [System.Environment]::NewLine + "Log files copied successfully. Exit: {0}." -f $logsExitCode | Write-Host -ForegroundColor Green
        }
        else
        {
            Terminate-Script ("Some log files were not copied from the server. Please verify if the credentials provided have access to the local specified in the configuration file and try again. Exit: {0}." -f $logsExitCode)
        }

        # Clean-up servers
        $cleanExitCode = CleanUp-Servers $servers

        # Check if clean-up was done
        if ($cleanExitCode  -eq 0)
        {
            [System.Environment]::NewLine + "Clean-up performed successfully. Exit: {0}." -f $cleanExitCode | Write-Host -ForegroundColor Green
        }
        else
        {
            Terminate-Script ("Some files were not deleted from the server. Please verify if the credentials provided have access to the local specified in the configuration file and try again. Exit: {0}." -f $cleanExitCode)
        }
    }
}

end
{
    # Goodbye message
    if (($checkPrerequisitesExitCode + $copyExitCode + $undeployExitCode + $uninstallExitCode + $installExitCode + $deployExitCode + $artifactsEnablingExitCode + $logsExitCode + $cleanExitCode) -eq 0)
    {
        [System.Environment]::NewLine + "Script ended without errors." | Write-Host -ForegroundColor Green
    }
    else
    {
        [System.Environment]::NewLine + "Errors occured at least in one of the previos steps. Please check the error messages." | Write-Host -ForegroundColor Red
    }

    Stop-Transcript

    "" | Write-Host
}
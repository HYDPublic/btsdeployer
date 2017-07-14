<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Common Functions Module
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Common Functions Module
.NOTES
    File Name      : btsdeployer_helper.ps1
    Author         : Willians Schallemberger Schneider, @schalleneider
    Prerequisite   : PowerShell v3
#>

function IIf
{
    [CmdletBinding()]
    param
    (
        [object]
            $statement,
        
        [object]
            $trueStatement,
        
        [object]
            $falseStatement
    )

    process
    {
        if ($statement -isnot "Boolean") { $_ = $statement }        
        if ($statement) { if ($trueStatement -is "ScriptBlock") { &$trueStatement } else { $trueStatement } }
        else { if ($falseStatement -is "ScriptBlock") { &$falseStatement } else { $falseStatement } }
    }
}

function Terminate-Script
{
    [CmdletBinding()]
    param
    (
        [string]
            $errorMessage
    )

    process
    {
        "" | Write-Host
        $errorMessage | Write-Error
        Stop-Transcript
        exit 1
    }
}

function Ask-UserAcceptance
{
    [CmdletBinding()]
    param  
    (
        [string]
            $question, 
        [int]
            $defaultChoice = 0
    )
    
    process
    {
        $yesOption = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Proceed with the operation."
        $noOption  = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does not proceed with the operation"
    
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yesOption, $noOption)
    
        return (!$Host.UI.PromptForChoice("", ([System.Environment]::NewLine + $question), $choices, $defaultChoice))
    }
}

function Get-MsBuild
{
    [CmdletBinding()]
    param()

    process
    {
        $dotNetVersion = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' | Sort-Object pschildname -Descending | Select-Object -First 1 -ExpandProperty pschildname
	
        #Include other info if .NET 4.0		
        if($dotNetVersion -eq "v4.0") 
        {
            $dotNetVersion = "v4.0.30319"
        }

        $msbuildPath = Join-Path $env:windir "Microsoft.NET\Framework\$dotNetVersion\MSBuild.exe"
	
        if (Test-Path $msbuildPath)
        {
            return $msbuildPath
        }
        else
        {
            Terminate-Script ("MsBuild.exe not found at the following address: {0}." -f $msbuildPath)
        }
    }
}

function Get-RemoteProgram
{
    [CmdletBinding()]
    param
    (
        [parameter(valueFromPipeline = $true, valueFromPipelineByPropertyName = $true, position = 0)]
        [string[]]
            $ComputerName = $env:COMPUTERNAME,
        
        [parameter(position = 0)]
        [string[]]
            $Property,
        
        [switch]
            $ExcludeSimilar,
        
        [int]
            $SimilarWord
    )

    begin {
        $RegistryLocation = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\',
                            'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'
        $HashProperty = @{}
        $SelectProperty = @('ProgramName','ComputerName')
        if ($Property) {
            $SelectProperty += $Property
        }
    }

    process {
        foreach ($Computer in $ComputerName) {
            $RegBase = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$Computer)
            $RegistryLocation | ForEach-Object {
                $CurrentReg = $_
                if ($RegBase) {
                    $CurrentRegKey = $RegBase.OpenSubKey($CurrentReg)
                    if ($CurrentRegKey) {
                        $CurrentRegKey.GetSubKeyNames() | ForEach-Object {
                            if ($Property) {
                                foreach ($CurrentProperty in $Property) {
                                    $HashProperty.$CurrentProperty = ($RegBase.OpenSubKey("$CurrentReg$_")).GetValue($CurrentProperty)
                                }
                            }
                            $HashProperty.ComputerName = $Computer
                            $HashProperty.ProgramName = ($DisplayName = ($RegBase.OpenSubKey("$CurrentReg$_")).GetValue('DisplayName'))
                            if ($DisplayName) {
                                New-Object -TypeName PSCustomObject -Property $HashProperty |
                                Select-Object -Property $SelectProperty
                            } 
                        }
                    }
                }
            } | ForEach-Object -Begin {
                if ($SimilarWord) {
                    $Regex = [regex]"(^(.+?\s){$SimilarWord}).*$|(.*)"
                } else {
                    $Regex = [regex]"(^(.+?\s){3}).*$|(.*)"
                }
                [System.Collections.ArrayList]$Array = @()
            } -Process {
                if ($ExcludeSimilar) {
                    $null = $Array.Add($_)
                } else {
                    $_
                }
            } -End {
                if ($ExcludeSimilar) {
                    $Array | Select-Object -Property *,@{
                        name       = 'GroupedName'
                        expression = {
                            ($_.ProgramName -split $Regex)[1]
                        }
                    } |
                    Group-Object -Property 'GroupedName' | ForEach-Object {
                        $_.Group[0] | Select-Object -Property * -ExcludeProperty GroupedName
                    }
                }
            }
        }
    }
}

function Execute-Process
{
    [CmdletBinding()]
    param
    (
        [string]
            $command, 
        [string]
            $arguments
    )

    process
    {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        
        $processInfo.FileName = $command
        $processInfo.Arguments = $arguments
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardOutput = $global:settings.SwitchVerboseOutput
        $processInfo.RedirectStandardError = $global:settings.SwitchVerboseOutput

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo

        $process.Start() > $null

        if ($global:settings.SwitchVerboseOutput)
        {
			"" | Write-Host
		
            # Output process output while process is active.
            while (!$process.HasExited)
            {
                $process.StandardOutput.ReadLine() | Write-Host -ForegroundColor DarkGray
            }
        }
        else
        {
            # Wait process to terminate.
            $process.WaitForExit()
        }

        return $process.ExitCode + $global:error.Count
    }
}
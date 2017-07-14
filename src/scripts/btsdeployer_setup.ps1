<#
.SYNOPSIS
    Automatic deployment procedure for BizTalk Applications
    Setup commands
.DESCRIPTION
    Automatic deployment procedure for BizTalk Applications
    Setup commands
.NOTES
    File Name      : btsdeployer_setup.ps1
    Author         : Willians Schallemberger Schneider, @schalleneider
    Prerequisite   : PowerShell v3
#>

# Enable CredSSP client role at BizTalk Server
Enable-WSManCredSSP -Role Client -DelegateComputer *.uapinc.com

# Check Allow Delegating Fresh Credentials
# 1. gpedit.msc
# 2. Computer Configuration > Computer Settings > Administrative Templates > System > Credentials Delegation
# 3. Allow Delegating Fresh Credentials -> Enabled
# 4. Add Servers to List: wsman/*.uapinc.com

# Enable CredSSP server role at BizTalk Server and SQL Server
Enable-WSManCredSSP -Role Server

# Enable Remote Access for Management at BizTalk Server
WinRM QuickConfig
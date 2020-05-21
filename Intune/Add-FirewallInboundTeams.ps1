<#PSScriptInfo

.VERSION 1.0

.GUID 6cf78ac7-2f77-45d9-aecf-685ac05109bf

.AUTHOR Sander Schouten (sander.schouten@bauhaus.nl)

.COMPANYNAME Bauhaus ArtITech B.V.

.COPYRIGHT 

.TAGS 

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES
Version 1.0: First Release

#>

<# 
.SYNOPSIS 
 Configures Firewall Rules for Teams.    

.DESCRIPTION 
 Configures Firewall Rules for Teams.

.PARAMETER Company
 Name of Company script is used for. Used for logging folders

#> 

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)] [String] $Company = "Intune-Powershell-Scripts"
)

$scriptName = "Add-FirewallInboundTeams"
if (-not (Test-Path "$($env:ProgramData)\$Company\$scriptName"))
{
    Mkdir "$($env:ProgramData)\$Company\$scriptName"
}
# Create a tag file just so Intune knows this was installed
Set-Content -Path "$($env:ProgramData)\$Company\$scriptName\$scriptName.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\$Company\$scriptName\$scriptName.log"

try {
    $users = Get-ChildItem (Join-Path -Path $env:SystemDrive -ChildPath 'Users') -Exclude 'Public', 'ADMINI*', 'default*'
    foreach ($user in $users) { 
        $TeamsDir = $user.fullname + "\appdata\local\Microsoft\Teams\current\teams.exe"
        Write-Host "Found: " $TeamsDir
        $firewallRuleName = "Teams.exe for user $($user.Name)"
        $ruleExist = Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue | Get-NetFirewallApplicationFilter| where-object {$_.program -eq $TeamsDir}
        if ($ruleExist) {
            Write-Host "Firewall rule exist. Allowing rule if Blocked. Enabling rule if Disabled." 
            Set-NetFirewallRule -DisplayName $firewallRuleName -Profile Any -Action Allow -Enabled True
        }
        else {
            Write-Host "Firewall rules do not exist. Creating..." 
            New-NetfirewallRule -DisplayName $firewallRuleName -Direction Inbound -Protocol TCP -Profile Any -Program $TeamsDir -Action Allow
            New-NetfirewallRule -DisplayName $firewallRuleName -Direction Inbound -Protocol UDP -Profile Any -Program $TeamsDir -Action Allow
        }
    }
} Finally {
    ### These aren't the scripts you're looking for...

    # starting the process that will remove this scripts policy from IME after it has run... (can't really do it while it's running!)
    # getting the name of the script file as it is run by IME
    # NOTICE! this will ONLY work when run by IME, so testing is not really easy.
    $scriptNameGUID = $MyInvocation.MyCommand.Name.Split(".")[0]
    $userGUID = $scriptNameGUID.Split("_")[0]
    $policyGUID = $scriptNameGUID.Split("_")[1]

    # generating the reg key path that we need to remove in order to have IME forget it ever ran this script.
    $regKey = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Policies\$userGUID\$policyGUID"

    # where to log the delete process
    $removalOutput = "$($env:ProgramData)\$Company\$scriptName\$scriptName-ForgetMe.log"

    # the delete registry key script
$deleteScript = @'
start-transcript "{0}";
Start-Sleep -Seconds 30;
Remove-Item -path "{1}" -Force -confirm:$false;
Write-Output "Next line should say false if all whent well...";
Test-Path -path "{1}";
Stop-Transcript;
'@ -f $removalOutput,$regKey

    $deleteScriptName = "c:\windows\temp\delete_$policyGUID.ps1"
    $deleteScript | Out-File $deleteScriptName -Force

    # starting a seperate powershell process that will wait 30 seconds before deleting the IME Policy registry key.
    $deleteProcess = New-Object System.Diagnostics.ProcessStartInfo "Powershell";
    $deleteProcess.Arguments = "-File " + $deleteScriptName
    $deleteProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($deleteProcess);

    Stop-Transcript
    exit
}
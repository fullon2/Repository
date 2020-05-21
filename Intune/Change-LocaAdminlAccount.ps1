<#PSScriptInfo

.VERSION 1.0

.GUID dbb8fc91-a253-4296-93a0-0f1a5533b778

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
 Create and update Local admin account.    

.DESCRIPTION 
 Create and update Local admin account.

.PARAMETER Company
 Name of Company script is used for. Used for logging folders

#> 

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)] [String] $Company = "Intune-Powershell-Scripts",
    [Parameter(Mandatory=$False)] [String] $LocalAdmin = "<name>",
    [Parameter(Mandatory=$False)] [String] $Adminpassword = "<pw>"
)

$scriptName = "Change-LocalAdminAccount"
if (-not (Test-Path "$($env:ProgramData)\$Company\$scriptName"))
{
    Mkdir "$($env:ProgramData)\$Company\$scriptName"
}
# Create a tag file just so Intune knows this was installed
Set-Content -Path "$($env:ProgramData)\$Company\$scriptName\$scriptName.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\$Company\$scriptName\$scriptName.log"

$ExpectedLocalUser = $LocalAdmin
$Password = ConvertTo-SecureString $Adminpassword -AsPlainText -Force

Function Create_LocalAdmin
{
    New-LocalUser $ExpectedLocalUser -Password $Password -FullName $ExpectedLocalUser -Description "Local Administrator account."
    Add-LocalGroupMember -Group "Administrators" -Member $ExpectedLocalUser
    Set-LocalUser -Name $ExpectedLocalUser -PasswordNeverExpires:$true
}

Try{
    ## Catch if not found
    $LocalAdminUser = Get-LocalUser -Name $ExpectedLocalUser -ErrorAction Stop 

    ## If an account is found update the password
    Set-LocalUser -Name $ExpectedLocalUser -Password $Password -PasswordNeverExpires:$true
    Write-Host "Account $ExpectedLocalUser already exists, updating password."
}Catch{
    Create_LocalAdmin
    Write-Host "Account $ExpectedLocalUser created."
}
Stop-Transcript
<#PSScriptInfo

.VERSION 1.0

.GUID 02d1b2da-2f5e-4a63-a4ac-61956a87eb55

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
 Set Regional and language settings.    

.DESCRIPTION 
 CSet Regional and language settings.

.PARAMETER Company
 Name of Company script is used for. Used for logging folders

#> 

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)] [String] $Company = "Intune-Powershell-Scripts",
    [Parameter(Mandatory=$False)] [String] $PrimaryLanguage = "en-NL",
    [Parameter(Mandatory=$False)] [String[]] $ExtraLanguages = ("en-US","nl-NL"),
    [Parameter(Mandatory=$False)] [String] $RegionalSetting = "nl-NL",
    [Parameter(Mandatory=$False)] [String[]] $InputCodes = ("0413:00020409","0409:00020409","2000:00020409"),
    [Parameter(Mandatory=$False)] [String] $GeoID = "176"
)

$scriptName = "Apply-UserLanguagePreferences-en-NL"
if (-not (Test-Path "$($env:ProgramData)\$Company\$scriptName"))
{
    Mkdir "$($env:ProgramData)\$Company\$scriptName"
}
# Create a tag file just so Intune knows this was installed
Set-Content -Path "$($env:ProgramData)\$Company\$scriptName\$scriptName.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\$Company\$scriptName\$scriptName.log"

# User-context script to set the Language List
# Set preferred languages
$Count = 0
$NewLanguageList = New-WinUserLanguageList -Language $PrimaryLanguage
Write-Host "Primary language set to $PrimaryLanguage."
$AllLanguages = New-object System.Collections.ArrayList
$AllLanguages.Add($PrimaryLanguage)
Foreach ($ExtraLanguage in $ExtraLanguages){
    Write-Host "Adding extra Language $ExtraLanguage..."
    $NewLanguageList.Add([Microsoft.InternationalSettings.Commands.WinUserLanguage]::new($ExtraLanguage))
    $AllLanguages.Add($ExtraLanguage)
}
# Add preferred Keyboards
Foreach ($Language in $AllLanguages){
    $NewLanguageList[$Count].InputMethodTips.Clear()
    Write-Host "Adding InputMethods for $Language."
    foreach ($InputCode in $InputCodes){
        $NewLanguageList[$Count].InputMethodTips.Add($InputCode)
    }
    $Count += 1
}
Write-Host "Setting Languagelist..."
Set-WinUserLanguageList $NewLanguageList -Force
# Make region settings independent of OS language
Set-WinCultureFromLanguageListOptOut -OptOut $True
# Set region to this Country
Write-Host "Setting Culture to $RegionalSetting."
Set-Culture $RegionalSetting
# Set the location to this location
Write-Host "Configure HomeLocation to $GeoID."
Set-WinHomeLocation -GeoId $GeoID
Stop-Transcript
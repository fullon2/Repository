<# 
.SYNOPSIS 
  This script will query the latest driverpack for current model.   

.DESCRIPTION
  This script will query the latest driverpack for current model.    

.PARAMETER Account
  Account with permission to remotely query SiteServer (powershell)
.PARAMETER Password
  Password of remote permission account
.PARAMETER SiteServer
  Name of the primairy SiteServer
.PARAMETER SiteCode
  SiteCode of SCCM Primary Site 
.PARAMETER OSVersion
  String to search for OS version
.PARAMETER DriverPackage
  Boolean for Driverpackage or normal package search
  Default is $True
.PARAMETER MatchProperty
  Property to query (comma seporated) model and os for
  Default "Description" property of package
.PARAMETER ModelName
  Overide model to query for (backupmethod)
  Default is Empty (will be queried)

.INPUTS
  None  

.OUTPUTS
  Log file stored in SMSTS.Log

.EXAMPLE 
  powershell -executionpolicy Bypass -file .\Get-DynamicDriverPackage.ps1
.EXAMPLE 
  powershell -executionpolicy Bypass -file .\Get-DynamicDriverPackage.ps1 -Account domain\user -Password ******** -SiteServer servername.domain -SiteCode 001

.NOTES
========================================================================================
  Filename:       Get-DynamicDriverPackage.ps1
  Version:        1.0.0
  Author:         Sander Schouten (sander.schouten@proactvx.com)
  Creation Date:  20171215
  Purpose/Change: First release 
  Reguirements:   Powershell 3.0
  Organization:   ProactVX B.V.
  Disclaimer:     This scripts is offered "as is" with no warranty. While this script is 
                  tested and working in my environment, it is recommended that you test
                  this script in a test environment before using in your production
                  environment.
========================================================================================
#> 

#-----------------------------------------------------------[Parameters]-----------------------------------------------------------
[CmdletBinding()]
param
(
    [string]$Account = "<domain>\<user>",
    [string]$Password = "********",
    [string]$SiteServer = "<sccmserverfqdn>",
    [string]$SiteCode = "<SiteCode>",
    [string]$OSVersion = "Win10X64_1709",
    [Bool]$DriverPackage = $True,
    [string]$MatchProperty = 'Description',
    [string]$ModelName = $Null
)

If (!$ModelName){
    $Manufacturer = (Get-WmiObject -Class win32_computersystem -Namespace root\cimv2).Manufacturer
    Write-Host -Object "Manufacturer: $Manufacturer"
    If($Manufacturer -like "*INTEL*"){
        $ModelName = (Get-WmiObject -Class win32_BaseBoard -Namespace root\cimv2).Product
    }ElseIf($Manufacturer -like "*LENOVO*"){
        $ModelName = (Get-WmiObject -Class win32_computersystemproduct -Namespace root\cimv2).Name
        $ModelName = $ModelName.Substring(0,4)
    }Else{
        #$ModelName = (Get-WmiObject -Class win32_computersystem -Namespace root\cimv2).Model
        $ModelName = (Get-WmiObject -Class win32_computersystemproduct -Namespace root\cimv2).Name
    }
}    
Write-Host -Object "Model: $ModelName"

$cred = New-Object System.Management.Automation.PSCredential -ArgumentList @($Account,(ConvertTo-SecureString -String $password -AsPlainText -Force))

Try{
    $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $tsenvInitialized = $true
}catch{
    Write-Host -Object '!! No Taskseqeunce environment !!'
    $tsenvInitialized = $false
}

If ($DriverPackage){
    $ScriptBlockContent = {
        param($SiteCode)
        $DriverPackages = Get-WmiObject -class sms_driverpackage -Namespace root\sms\site_$SiteCode | Select-Object pkgsourcepath, Description, ISVData, ISVString, Manufacturer, MifFileName, MifName, MifPublisher, MIFVersion, Name, PackageID, ShareName, Version
    }
}else{
    $ScriptBlockContent = {
        param($SiteCode)
        $DriverPackages = Get-WmiObject -class sms_package -Namespace root\sms\site_$SiteCode -filter "name like 'Driverpack%'" | Select-Object pkgsourcepath, Description, ISVData, ISVString, Manufacturer, MifFileName, MifName, MifPublisher, MIFVersion, Name, PackageID, ShareName, Version
    }
}
Try{
    $Session = New-PSSession -ComputerName $SiteServer -Credential $cred
    Invoke-Command -Session $Session -ScriptBlock $ScriptBlockContent -ArgumentList $SiteCode
    $AllDriverPackages = Invoke-Command -Session $Session -ScriptBlock {$DriverPackages}
    $SiteServerAccess = $true
}catch{
    Write-Host -Object 'No access to Site server'
    $SiteServerAccess = $False
}

If ($SiteServerAccess){
    $PackageID = (($AllDriverPackages | ? {($_.$MatchProperty.Split(',').Contains($ModelName)) -and ($_.$MatchProperty.Split(',').Contains($OSVersion))})|Sort-Object -Property Version -Descending |Select-Object -First 1).PackageID
    Write-Host -Object "Selected Package: $PackageID"
    Remove-PSSession $Session
}
If (($tsenvInitialized)-and($PackageID)){
    $tsenv.Value('OSDDownloadDownloadPackages') = $PackageID
}


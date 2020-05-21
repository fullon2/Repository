<#PSScriptInfo

.VERSION 1.1

.GUID 743099e2-3753-4aff-8d9b-af50322ef44b

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
Version 1.1: Support for OU. Delay and repetition Scheduled Task

#>

<# 
.SYNOPSIS 
 Create legacy drivemappings.    

.DESCRIPTION 
 This script performs network drive mappings with PowerShell and is based on the intune-drive-mapping-generator (https://intunedrivemapping.azurewebsites.net).
 When executed under SYSTEM authority a scheduled task is created to ensure recurring script execution on each user logon.

.NOTES
 Original Author: Nicola Suter, nicolonsky tech: https://tech.nicolonsky.ch

.PARAMETER Company
 Name of Company script is used for. Used for logging folders

#> 

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)] [String] $Company = "Intune-Powershell-Scripts"
)
###########################################################################################
# Start transcript for logging															  #
###########################################################################################

if (-not (Test-Path "$($env:ProgramData)\$Company\DriveMapping"))
{
    Mkdir "$($env:ProgramData)\$Company\DriveMapping"
}
Set-Content -Path "$($env:ProgramData)\$Company\DriveMapping\DriveMapping.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\$Company\DriveMapping\DriveMapping.log"

###########################################################################################
# Input values from generator															  #
###########################################################################################

$driveMappingJson='[{"Path":"\\\\<serverfqdn>\\<sharename>","DriveLetter":"N","Label":"<mappinglabel>","Id":1,"GroupFilter":"<adgroup>","OUFilter":null}]'

$driveMappingConfig= $driveMappingJson | ConvertFrom-Json

###########################################################################################
# Helper function to determine a users group membership									  #
###########################################################################################

# Kudos for Tobias Renström who showed me this!
function Get-ADGroupMembership {
	param(
		[parameter(Mandatory=$true)]
		[string]$UserPrincipalName
	)
	process{

		try{

			$Searcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher
			$Searcher.Filter = "(&(userprincipalname=$UserPrincipalName))"
			$Searcher.SearchRoot = "LDAP://$env:USERDNSDOMAIN"
			$DistinguishedName = $Searcher.FindOne().Properties.distinguishedname
			$Searcher.Filter = "(member:1.2.840.113556.1.4.1941:=$DistinguishedName)"
			
			[void]$Searcher.PropertiesToLoad.Add("name")
			
			$List = [System.Collections.Generic.List[String]]@()

			$Results = $Searcher.FindAll()
			
			foreach ($Result in $Results) {
				$ResultItem = $Result.Properties
				[void]$List.add($ResultItem.name)
			}
		
			$List

		}catch{
			#Nothing we can do
			Write-Warning $_.Exception.Message
		}
	}
}

###########################################################################################
# Helper function to determine a users first OU     									  #
###########################################################################################

function Get-UserOU {
	param(
		[parameter(Mandatory=$true)]
		[string]$UserPrincipalName
	)
	process{

		try{

			$Searcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher
			$Searcher.Filter = "(&(userprincipalname=$UserPrincipalName))"
			$Searcher.SearchRoot = "LDAP://$env:USERDNSDOMAIN"
			$DistinguishedName = $Searcher.FindOne().Properties.distinguishedname
            $OU = $DistinguishedName -replace '.+?,OU=(.+?),(?:OU|DC)=.+','$1'
            $OU

		}catch{
			#Nothing we can do
			Write-Warning $_.Exception.Message
		}
	}
}


###########################################################################################
# Get current group membership for the group filter capabilities						  #
###########################################################################################

if ($driveMappingConfig.GroupFilter){
	try{
		#check if running as user and not system
		if (-not ($(whoami -user) -match "S-1-5-18")){

			$groupMemberships = Get-ADGroupMembership -UserPrincipalName $(whoami -upn)
		}
	}catch{
		#nothing we can do
	}	 
}

###########################################################################################
# Get current UserOU for the OU filter capabilities	                					  #
###########################################################################################

if ($driveMappingConfig.OUFilter){
	try{
		#check if running as user and not system
		if (-not ($(whoami -user) -match "S-1-5-18")){

			$UserOU = Get-UserOU -UserPrincipalName $(whoami -upn)
		}
	}catch{
		#nothing we can do
	}	 
}

###########################################################################################
# Mapping network drives																  #
###########################################################################################
#Get PowerShell drives and rename properties
try{

	$psDrives = Get-PSDrive | Select-Object @{N="DriveLetter"; E={$_.Name}}, @{N="Path"; E={$_.DisplayRoot}}

}catch{

	Write-Warning $_.Exception.Message
}

#iterate through all network drive configuration entries
$driveMappingConfig.GetEnumerator() | ForEach-Object {

	try{

		#check if variable in unc path exists, e.g. for $env:USERNAME
		if ($PSItem.Path -match '\$env:'){

			$PsItem.Path=$ExecutionContext.InvokeCommand.ExpandString($PSItem.Path)
			
		}

		#if label is null we need to set it to empty in order to avoid error
		if ($PSItem.Label -eq $null){

			$Psitem.Label = ""
		}
        $MapDrive = $False
        #check if user needs drive mapping based on group or OU.
		if (($PSItem.GroupFilter -ne $null -and $PSItem -eq $Null) -and $groupMemberships -contains $PSItem.GroupFilter){ $MapDrive = $true}
		if (($PSItem.GroupFilter -ne $null -and $PSItem -ne $Null) -and $groupMemberships -contains $PSItem.GroupFilter -and $UserOU -eq $PSItem.OUFilter){ $MapDrive = $true}
		if (($PSItem.GroupFilter -eq $null -and $PSItem -ne $Null) -and $UserOU -eq $PSItem.OUFilter){ $MapDrive = $true}
		if ($PSItem.GroupFilter -eq $null -and $PSItem -eq $Null){ $MapDrive = $true}
		If ($MapDrive -eq $true){
            #check if the drive is already connected with an identical configuration
        	if ( -not ($psDrives.Path -contains $PSItem.Path -and $psDrives.DriveLetter -contains $PSItem.DriveLetter)){
                #check if drive exists - but with wrong config - to delete it
			    if($psDrives.Path -contains $PSItem.Path -or $psDrives.DriveLetter -contains $PSItem.DriveLetter){
                    Write-Output "Removing wrong network drive $($PSItem.Path)"
				    Get-PSDrive | Where-Object {$_.DisplayRoot -eq $PSItem.Path -or $_.Name -eq $PSItem.DriveLetter} | Remove-PSDrive -ErrorAction SilentlyContinue
			    }
				Write-Output "Mapping network drive $($PSItem.Path)"
				$null = New-PSDrive -PSProvider FileSystem -Name $PSItem.DriveLetter -Root $PSItem.Path -Description $PSItem.Label -Persist -Scope global -EA SilentlyContinue
				(New-Object -ComObject Shell.Application).NameSpace("$($PSItem.DriveLetter):").Self.Name=$PSItem.Label
		    }else{
				
			    Write-Output "Drive already exists with same DriveLetter and Path"
		    }
		}
	}catch{

		Write-Warning $_.Exception.Message
	}
}

# Fix to ensure drives are mapped as persistent!
Get-ChildItem -Path HKCU:\Network -ErrorAction SilentlyContinue | ForEach-Object {New-ItemProperty -Name ConnectionType -Value 1 -Path $_.PSPath -Force -ErrorAction SilentlyContinue}

###########################################################################################
# End & finish transcript																  #
###########################################################################################

Stop-transcript

###########################################################################################
# Done																					  #
###########################################################################################

#!SCHTASKCOMESHERE!#

###########################################################################################
# If this script is running under system (IME) scheduled task is created  (recurring)	  #
###########################################################################################

$CompanyPath = "$($env:ProgramData)\$Company\DriveMapping"

Start-Transcript -Path $(Join-Path -Path $CompanyPath -ChildPath "IntuneDriveMappingScheduledTask.log")

if ($(whoami -user) -match "S-1-5-18"){

	Write-Output "Running as System --> creating scheduled task which will run on user logon"

	###########################################################################################
	# Get the current script path and content and save it to the client						  #
	###########################################################################################

	$currentScript= Get-Content -Path $($PSCommandPath)
	
	$schtaskScript=$currentScript[(0) .. ($currentScript.IndexOf("#!SCHTASKCOMESHERE!#") -1)]

	$scriptSavePath=$CompanyPath

	if (-not (Test-Path $scriptSavePath)){

		New-Item -ItemType Directory -Path $scriptSavePath -Force
	}

	$scriptSavePathName="DriveMappping.ps1"

	$scriptPath= $(Join-Path -Path $scriptSavePath -ChildPath $scriptSavePathName)

	$schtaskScript | Out-File -FilePath $scriptPath -Force

	###########################################################################################
	# Create dummy vbscript to hide PowerShell Window popping up at logon					  #
	###########################################################################################

	$vbsDummyScript = "
	Dim shell,fso,file

	Set shell=CreateObject(`"WScript.Shell`")
	Set fso=CreateObject(`"Scripting.FileSystemObject`")

	strPath=WScript.Arguments.Item(0)

	If fso.FileExists(strPath) Then
		set file=fso.GetFile(strPath)
		strCMD=`"powershell -nologo -executionpolicy ByPass -command `" & Chr(34) & `"&{`" &_ 
		file.ShortPath & `"}`" & Chr(34) 
		shell.Run strCMD,0
	End If
	"

	$scriptSavePathName="IntuneDriveMapping-VBSHelper.vbs"

	$dummyScriptPath= $(Join-Path -Path $scriptSavePath -ChildPath $scriptSavePathName)
	
	$vbsDummyScript | Out-File -FilePath $dummyScriptPath -Force

	$wscriptPath = Join-Path $env:SystemRoot -ChildPath "System32\wscript.exe"

	###########################################################################################
	# Register a scheduled task to run for all users and execute the script on logon		  #
	###########################################################################################

	$schtaskName= "IntuneDriveMapping"
	$schtaskDescription="Map network drives from intune-drive-mapping-generator."

	$trigger = New-ScheduledTaskTrigger -AtLogOn
    $trigger.Delay = 'PT1M'
	#Execute task in users context
	$principal= New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -Id "Author"
	#call the vbscript helper and pass the PosH script as argument
	$action = New-ScheduledTaskAction -Execute $wscriptPath -Argument "`"$dummyScriptPath`" `"$scriptPath`""
	$settings= New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
	
	$task=Register-ScheduledTask -TaskName $schtaskName -Trigger $trigger -Action $action  -Principal $principal -Settings $settings -Description $schtaskDescription -Force
    $task.triggers.Repetition.Duration = 'P1D'
    $task.triggers.Repetition.Interval = 'PT30M'
    $task | Set-ScheduledTask

	Start-ScheduledTask -TaskName $schtaskName
}

Stop-Transcript

###########################################################################################
# Done																					  #
###########################################################################################

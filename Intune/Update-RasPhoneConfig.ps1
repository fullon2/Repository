<#PSScriptInfo

.VERSION 1.2

.GUID ABB82E80-2841-48B1-8C1D-AFFCE9D37760

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
Version 1.1: Fixed User Logging
Version 1.2: Fixed IKEv2 IPsec policy 

#>

<# 
.SYNOPSIS 
 Configure RASPhone.Pbk.    

.DESCRIPTION 
 This script performs changes in rasphone.pbk with PowerShell and is based on logics from 
 https://intunedrivemapping.azurewebsites.net and update-rasphone.ps1 https://github.com/richardhicks/aovpn.
 When executed under SYSTEM authority a scheduled task is created to ensure recurring script execution on each user logon.

.NOTES
 Original Author: Nicola Suter, nicolonsky tech: https://tech.nicolonsky.ch

.PARAMETER Company
 Name of Company script is used for. Used for logging folders

.PARAMETER CustomScriptName
 Name of the scheduled script. Also sed for logging folders

#> 

[CmdletBinding()]
Param(
	[Parameter(Mandatory=$False)] [String] $Company = "Company",
	[Parameter(Mandatory=$False)] [String] $CustomScriptName = "ModifyRasphonePbk"
)
###########################################################################################
# Start transcript for logging															  #
###########################################################################################


# Start logging

if (-not ($(whoami -user) -match "S-1-5-18")){
	if (-not (Test-Path "$($env:localappdata)\$Company\$CustomScriptName"))
	{
		Mkdir "$($env:localappdata)\$Company\$CustomScriptName"
	}
	Start-Transcript "$($env:localappdata)\$Company\$CustomScriptName\$CustomScriptName.log"
} else {
	if (-not (Test-Path "$($env:ProgramData)\$Company\$CustomScriptName"))
	{
		Mkdir "$($env:ProgramData)\$Company\$CustomScriptName"
	}
	Set-Content -Path "$($env:ProgramData)\$Company\$CustomScriptName\$CustomScriptName.ps1.tag" -Value "Installed"
	Start-Transcript "$($env:ProgramData)\$Company\$CustomScriptName\$CustomScriptName.log"
}

###########################################################################################
# Configure RasPhone.pbk             					                                  #
###########################################################################################

#check if running as user and not system
if (-not ($(whoami -user) -match "S-1-5-18")){
	Write-Output "Running as User"
	$RasphonePath = "$env:appdata\Microsoft\Network\Connections\Pbk\rasphone.pbk"
	$ProfileName = "$($Company) Always-On VPN"
} else {
	Write-Output "Running as System"
	$RasphonePath = "C:\ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
	$ProfileName = "$($Company) Always-On VPN Device Tunnel"
}
# // Ensure that rasphone.pbk exists
If (!(Test-Path $RasphonePath)) {
    Write-Warning "The file $RasphonePath does not exist. Exiting script."
} Else {
    # // Create empty hashtable
    $Settings = @{ }

    # // Set preferred VPN protocol
    if (-not ($(whoami -user) -match "S-1-5-18")){
        $Settings.Add('VpnStrategy', '14')
    }

	# // Add CustomIPSecPolicies
    if (-not ($(whoami -user) -match "S-1-5-18")){
		$Settings.Add('CustomIPSecPolicies', '020000000200000003000000030000000200000003000000')
        $Settings.Add('NumCustomPolicy', "1")
    }
    # // Set IPv4 and IPv6 interface metrics
    $Settings.Add('IpInterfaceMetric', '10')
    $Settings.Add('Ipv6InterfaceMetric', '10')

    # // If IKE mobility is enabled, define network outage time
    $Settings.Add('DisableMobility', '0')
    $Settings.Add('NetworkOutageTime', '30')

    # // Function to update rasphone.pbk settings
    Function Update-Rasphone {

        [CmdletBinding(SupportsShouldProcess)]

        Param(
            [string]$Path,
            [string]$ProfileName,
            [hashtable]$Settings
        )
        
        $RasphoneProfiles = (Get-Content $Path -Raw) -split "\[" | Where-Object { $_ -match "\w+" } # "`n\s?`n\["
        $Output = @()
        
        # // Create a hashtable of VPN profiles
        Write-Verbose "Searching for VPN profiles..."
        $ProfileHash = [ordered]@{ }
        
        ForEach ($RasphoneProfile in $RasphoneProfiles) {
        
            $RasphoneProfileName = [regex]::Match($RasphoneProfile, ".*(?=\])")
            Write-Verbose "Found VPN profile ""$RasphoneProfileName""..."
            $ProfileHash.Add($RasphoneProfileName, $RasphoneProfile)

        }
        
        $Profiles = $ProfileHash.GetEnumerator()
        
        ForEach ($Name in $ProfileName) {
        
            Write-Verbose "Searching for VPN profile ""$Name""..."
        
            ForEach ($Entry in $Profiles) {
        
                If ($Entry.Name -Match "^$Name$") {
        
                    Write-Verbose "Updating settings for ""$($Entry.Name)""..."
                    $RasphoneProfile = $Entry.Value
                    $Settings.GetEnumerator() | ForEach-Object {
        
                        $SettingName = $_.Name
                        Write-Verbose "Searching VPN profile ""$($Entry.Name)"" for setting ""$Settingname""..."
                        $Value = $_.Value
                        $Old = "$SettingName=.*\s?`n"
                        $New = "$SettingName=$value`n"
						
                        If ($RasphoneProfile -Match $Old) {
							If (!($matches[0] -match $new)) {
									Write-Verbose "Setting ""$SettingName"" to ""$Value""..."
									$RasphoneProfile = $RasphoneProfile -Replace $Old, $New

									# // Set a flag indicating the file should be updated
									$Changed = $True
							} Else {
								Write-Verbose "Setting ""$SettingName"" allready set correct..."
							}
                        } ElseIf ($new -Match "CustomIPSecPolicies") {
                            Write-Verbose "Adding setting new ""$SettingName"" with value ""$Value"" under ""$($entry.name)""."
							$RasphoneProfile = $RasphoneProfile -Replace "NumCustomPolicy=.*\s?`n", "NumCustomPolicy=1`r`nCustomIPSecPolicies=020000000200000003000000030000000200000003000000`n"
                        } Else {
							Write-Warning "Could not find setting ""$SettingName"" under ""$($entry.name)""."
						}
        
                    } # ForEach setting
					
					# Add RasphoneProfile to Output
                    $Output += $RasphoneProfile -Replace '^\[?.*\]', "[$($entry.name)]"
                    $Output = $Output.Trimstart()
        
                } Else {
                    # Keep the entry
                    $Output += $Entry.value -Replace '^\[?.*\]', "[$($entry.name)]"
                    $Output = $output.Trimstart()
                }
        
            } # ForEach entry in profile hashtable
        
            If ( -Not $Changed) {
                Write-Warning "No changes were made to VPN profile ""$name""."
            }
        } # ForEach Name in ProfileName
        
        # // Only update the file if changes were made
        If (($Changed) -AND ($PsCmdlet.ShouldProcess($Path, "Update rasphone.pbk"))) {
			
            Write-Verbose "Updating $Path..."
            $Output | Out-File -FilePath $Path -Encoding ASCII
        

        } # Whatif
    } # End Function Update-Rasphone

    Update-Rasphone -Path $RasphonePath -ProfileName $ProfileName -Settings $Settings -Verbose
}
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

$CompanyPath = "$($env:ProgramData)\$Company\$CustomScriptName"
$ScheduledTaskLog =  $CustomScriptName + "-ScheduledTask.log"
Start-Transcript -Path $(Join-Path -Path $CompanyPath -ChildPath $ScheduledTaskLog)

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

	$scriptSavePathName= $CustomScriptName + ".ps1"

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

	$scriptSavePathName= $CustomScriptName + "-VBSHelper.vbs"

	$dummyScriptPath= $(Join-Path -Path $scriptSavePath -ChildPath $scriptSavePathName)
	
	$vbsDummyScript | Out-File -FilePath $dummyScriptPath -Force

	$wscriptPath = Join-Path $env:SystemRoot -ChildPath "System32\wscript.exe"

	###########################################################################################
	# Register a scheduled task to run for all users and execute the script on logon		  #
	###########################################################################################

	$schtaskName = $CustomScriptName + "-User"
	$schtaskDescription = $CustomScriptName + "-User"

	$trigger = New-ScheduledTaskTrigger -AtLogOn
    #$trigger.Delay = 'PT1M'
	#Execute task in users context
	$principal= New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -Id "Author"
	#call the vbscript helper and pass the PosH script as argument
	$action = New-ScheduledTaskAction -Execute $wscriptPath -Argument "`"$dummyScriptPath`" `"$scriptPath`""
	$settings= New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
	
	$task=Register-ScheduledTask -TaskName $schtaskName -Trigger $trigger -Action $action  -Principal $principal -Settings $settings -Description $schtaskDescription -Force
    $task.triggers.Repetition.Duration = 'P90D'
    $task.triggers.Repetition.Interval = 'PT30M'
    $task | Set-ScheduledTask

	Start-ScheduledTask -TaskName $schtaskName

	###########################################################################################
	# Register a scheduled task to run as SYSTEM and execute the script on logon		  #
	###########################################################################################

	$schtaskName = $CustomScriptName + "-System"
	$schtaskDescription = $CustomScriptName + "-System"

	$trigger = New-ScheduledTaskTrigger -AtStartup
    #$trigger.Delay = 'PT1M'
	#Execute task in users context
	$principal= New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
	#call the vbscript helper and pass the PosH script as argument
	$action = New-ScheduledTaskAction -Execute $wscriptPath -Argument "`"$dummyScriptPath`" `"$scriptPath`""
	$settings= New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
	
	$task=Register-ScheduledTask -TaskName $schtaskName -Trigger $trigger -Action $action  -Principal $principal -Settings $settings -Description $schtaskDescription -Force
    $task.triggers.Repetition.Duration = 'P90D'
    $task.triggers.Repetition.Interval = 'PT30M'
    $task | Set-ScheduledTask

	Start-ScheduledTask -TaskName $schtaskName

}

Stop-Transcript

###########################################################################################
# Done																					  #
###########################################################################################

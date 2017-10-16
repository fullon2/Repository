<# 
.SYNOPSIS 
  This script will assign and revoke Office 365 Licenses.   

.DESCRIPTION
  This script will assign and revoke Office 365 Licenses based groupmembership.
  An xml input file will be used configuration.    

.PARAMETER ConfigFile
  Path to a configuration file with groups and licenses.
  Default file is Licenses.xml
.PARAMETER CredentialFile
  Path to a signed credential file to be used to connect to O365.
  Default file is LicenseManagerCredential.xml
.PARAMETER Email
  Enable email function on errors
  Default is false

.INPUTS
  License configuration XML file and optional Credential XML file  

.OUTPUTS
  Log file stored in <scriptpath>\Assign-O365-Licenses_Logging

.EXAMPLE 
  powershell -executionpolicy Bypass -file .\Assign-O365-Licenses.ps1
.EXAMPLE 
  powershell -executionpolicy Bypass -file .\Assign-O365-Licenses.ps1 -ConfigFile .\file.xml -CredentialFile .\cred.xml

.NOTES
========================================================================================
  Filename:       Assign-O365_Licenses.ps1
  Version:        2.4.1
  Author:         Sander Schouten (sander.schouten@proactvx.com)
  Creation Date:  20171013
  Purpose/Change: Corrected MSolUser ServicePlans query 
  Reguirements:   Powershell 3.0, MSOnline Module and PowerShellLogging module
  Organization:   ProactVX B.V.
  Disclaimer:     This scripts is offered "as is" with no warranty. While this script is 
                  tested and working in my environment, it is recommended that you test
                  this script in a test environment before using in your production
                  environment.
========================================================================================
#> 

#-----------------------------------------------------------[Parameters]-----------------------------------------------------------
[CmdletBinding(DefaultParametersetName='None')]
param(
    [Parameter()] [ValidateScript({Test-Path $_ })] [string]$ConfigFile = "$PSScriptRoot\Licenses.xml",
    [Parameter()] [ValidateScript({Test-Path $_ })] [string]$CredentialFile = "$PSScriptRoot\LicenseManagerCredential.xml",
    [Parameter(ParameterSetName='Email',Mandatory=$false)] [switch]$Email,      
    [Parameter(ParameterSetName='Email',Mandatory=$true)] [string]$SMTPServer,
    [Parameter(ParameterSetName='Email',Mandatory=$false)] [string]$SMTPPort = '25',
    [Parameter(ParameterSetName='Email',Mandatory=$true)] [string]$EmailFrom,
    [Parameter(ParameterSetName='Email',Mandatory=$true)] [string]$EmailTo,
    [Parameter(ParameterSetName='Email',Mandatory=$false)] [string]$EmailSubject = "O365 licensing errors",
    [Parameter(ParameterSetName='Email',Mandatory=$false)] [string]$SMTPUser,
    [Parameter(ParameterSetName='Email',Mandatory=$false)] [string]$SMTPPassword,
    [Parameter(ParameterSetName='Email',Mandatory=$false)] [string]$SMTPCredentialFile = "$PSScriptRoot\EmailCredential.xml"
)

#----------------------------------------------------------[Declarations]----------------------------------------------------------
#Set BufferSize (for logging)
$pshost = get-host
$pswindow = $pshost.ui.rawui
$newsize = $pswindow.buffersize
$newsize.height = 5000
$newsize.width = 300
$pswindow.buffersize = $newsize

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
#Import Required PowerShellLogging Module
If (Get-Module -ListAvailable -Name PowerShellLogging) {
    If (!(Get-module PowerShellLogging )) {Import-Module PowerShellLogging}
} else {
    Write-Warning "WARNING: Module PowerShellLogging does not exist"
    Exit
}
#Enable Logging
$LogDate = get-date -Format "yyyy-MM-dd"
$LogTime = get-date -Format "yyyy-MM-dd_HH:mm"
$LogFileName = "Assign-O365-Licenses-$LogDate.log"
If (!(Test-Path $PSScriptRoot\Assign-O365-Licenses_Logging)){New-Item -ItemType directory -Path $PSScriptRoot\Assign-O365-Licenses_Logging}
$LogFile = Enable-LogFile -Path $PSScriptRoot\Assign-O365-Licenses_Logging\$LogFileName
Write-Output "**************************************************************************"
Write-Output "********************* Start Logging ($LogTime) *******************"
Write-Output "**************************************************************************"
$SendEmail = $False
$EmailBody += ("The following errors occured:" + "`r`n")

#Import Required MSOnline Module
If (Get-Module -ListAvailable -Name MSOnline) {
    If (!(Get-module MSOnline )) {Import-Module MSOnline}
} else {
    Write-Warning "* WARNING: Module MSOnline does not exist"
    Write-Output "**************************** Stop Logging ********************************"
    $EmailBody += ("- WARNING: Module MSOnline does not exist" + "`r`n")
    $ErrorOccured = $True
}

#Email Credentials
#Option 1
If (Test-Path $SMTPCredentialFile){$EmailCred = Import-Clixml $SMTPCredentialFile}
#Option 2
ElseIf (($SMTPUser) -and ($SMTPPassword)){$EmailCred = New-Object System.Management.Automation.PSCredential -ArgumentList $SmtpUser, $($smtpPassword | ConvertTo-SecureString -AsPlainText -Force)}
Else{} 

#Office 365 Admin Credentials
#Option 1
If (Test-Path $CredentialFile){$CloudCred = Import-Clixml $CredentialFile}
#Option 2
Else {$CloudCred = get-credential -Message "Office 365 Credential"}
#Option 3
#$CloudUsername = '<serviceaccount>@<tenantname>.onmicrosoft.com'
#$CloudPassword = ConvertTo-SecureString '***********' -AsPlainText -Force
#$CloudCred = New-Object System.Management.Automation.PSCredential $CloudUsername, $CloudPassword

#Connect to Office 365
try {
	Connect-MsolService -Credential $CloudCred -ErrorAction Stop -WarningAction Stop
    $ConnectedOrg = (Get-MsolCompanyInformation).Displayname
	Write-Output "* Connected to Azure AD of $ConnectedOrg"
    Write-Output "**************************************************************************"
} catch {
	Write-Warning "* WARNING: Error Connecting to Azure AD"
    Write-Output "**************************** Stop Logging ********************************"
    $EmailBody += ("- WARNING: Error Connecting to Azure AD" + "`r`n")
    $ErrorOccured = $True
}


#Load Configuration File
If (!(Test-Path $ConfigFile)){
    Write-Output "* WARNING: License/config file $ConfigFile does not exist!"
    Write-Output "**************************** Stop Logging ********************************"
    $EmailBody += ("- WARNING: License/config file $ConfigFile does not exist!" + "`r`n")
    $ErrorOccured = $True
}Else {
    try {
        [xml]$XMLDocument = Get-Content -Path $ConfigFile
    } catch {
	    Write-Warning "* WARNING: License/config file $ConfigFile is corrupt!"
        Write-Output "**************************** Stop Logging ********************************"
        $EmailBody += ("- WARNING: License/config file $ConfigFile is corrupt!" + "`r`n")
        $ErrorOccured = $True
    }
}

If ($ErrorOccured){
    If ($SendEmail){
        If ($EmailCred){
            Send-MailMessage -To $EmailTo -from $EmailFrom -subject $EmailSubject -body $EmailBody -smtpServer $SMTPServer -Attachments $LogFile.path -Port $SMTPPort -Credential $EmailCred
        }Else{
            Send-MailMessage -To $EmailTo -from $EmailFrom -subject $EmailSubject -body $EmailBody -smtpServer $SMTPServer -Attachments $LogFile.path -Port $SMTPPort
        }
    }
    $LogFile | Disable-LogFile
    Exit
}

#-----------------------------------------------------------[Functions]------------------------------------------------------------
function Get-JDMsolGroupMember { 
    <#
    .SYNOPSIS
        The function enumerates Azure AD Group members with the support for nested groups.
    .EXAMPLE
        Get-JDMsolGroupMember 6d34ab03-301c-4f3a-8436-98f873ec121a
    .EXAMPLE
        Get-JDMsolGroupMember -ObjectId  6d34ab03-301c-4f3a-8436-98f873ec121a -Recursive
    .EXAMPLE
        Get-MsolGroup -SearchString "Office 365 E5" | Get-JDMsolGroupMember -Recursive
    .NOTES
        Author   : Johan Dahlbom, johan[at]dahlbom.eu
        Blog     : 365lab.net 
        The script are provided �AS IS� with no guarantees, no warranties, and it confer no rights.
    #>
     
        param(
            [CmdletBinding(SupportsShouldProcess=$true)]
            [Parameter(Mandatory=$true, ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)]
            [ValidateScript({Get-MsolGroup -ObjectId $_})]
            $ObjectId,
            [switch]$Recursive
        )
        begin {
            $MSOLAccountSku = Get-MsolAccountSku -ErrorAction Ignore -WarningAction Ignore
            if (-not($MSOLAccountSku)) {
                throw "Not connected to Azure AD, run Connect-MsolService"
            }
        } 
        process {
            Write-Verbose -Message "Enumerating group members in group $ObjectId"
            $UserMembers = Get-MsolGroupMember -GroupObjectId $ObjectId -MemberObjectTypes User -All
            if ($PSBoundParameters['Recursive']) {
                $GroupsMembers = Get-MsolGroupMember -GroupObjectId $ObjectId -MemberObjectTypes Group -All
                if ($GroupsMembers) {
                    Write-Verbose -Message "$ObjectId have $($GroupsMembers.count) group(s) as members, enumerating..."
                    $GroupsMembers | ForEach-Object -Process {
                        Write-Verbose "Enumerating nested group $($_.Displayname) ($($_.ObjectId))"
                        $UserMembers += Get-JDMsolGroupMember -Recursive -ObjectId $_.ObjectId 
                    }
                }
            }
            Write-Output ($UserMembers | Sort-Object -Property EmailAddress -Unique) 
             
        }
        end {
        }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Set Location for O365
$UsageLocation = $XMLDocument.Licenses.Usagelocation

#Set Customobject for MSOLUser propperties
$LicensedUserDetails = Get-MsolUser -All | Where-Object {$_.IsLicensed -eq 'True'} | ForEach-Object {
  [pscustomobject]@{
                        UserPrincipalName = $_.UserPrincipalName
                        Licenses = $_.Licenses| ForEach-Object {
                        [pscustomobject]@{
                            LicenseName = $_.AccountSkuId
    						DisabledPlans = ($_ | Select-Object -ExpandProperty ServiceStatus | Where-Object -Property ProvisioningStatus -EQ "Disabled").ServicePlan.ServiceName
    						EnabledPlans = ($_ | Select-Object -ExpandProperty ServiceStatus | Where-Object -Property ProvisioningStatus -EQ "Success").ServicePlan.ServiceName
                            AvailablePlans = ($_ | Select-Object -ExpandProperty ServiceStatus).ServicePlan.ServiceName
                            }
                            }
                        }
  }
   
#Create array for users to change or delete
$UsersToDelete = @()
  
Foreach ($license in $XMLDocument.Licenses.License) {
    #Get current group name and ObjectID from Hashtable
	$GroupNameBasic = $License.GroupBasic
    $GroupNameFull = $License.GroupFull
    $LicenseSKU = $License.LicenseSKU
    $EnabledPlans = $License.EnabledPlans.EnabledPlan
    $GroupIDBasic = (Get-MsolGroup -All | Where-Object {$_.DisplayName -eq $GroupNameBasic}).ObjectId
    $GroupIDFull = (Get-MsolGroup -All | Where-Object {$_.DisplayName -eq $GroupNameFull}).ObjectId
    $AccountSKU = Get-MsolAccountSku | Where-Object {$_.AccountSKUID -eq $LicenseSKU}
    $AvailablePlans = $AccountSKU.ServiceStatus.ServicePlan.ServiceName
    Write-Output "Processing $LicenseSKU with group $GroupNameFull and $GroupNameBasic (ObjectGuid $GroupIDFull and $GroupIDBasic)..."
	
	If ($EnabledPlans) {
		$DisabledPlans = (Compare-Object -ReferenceObject $AvailablePlans -DIfferenceObject $EnabledPlans).InputObject
		$LicenseOptionHt = @{
			AccountSkuId = $AccountSKU.AccountSkuId
			DisabledPlans = $DisabledPlans
		}
		$LicenseOptions = New-MsolLicenseOptions @LicenseOptionHt
        Write-Output "- DisabledPlans: $DisabledPlans"
    	Write-Output "- Enabled plans: $EnabledPlans"
	}

    #Get all members of the group in current scope. Also nested groups.
    $GroupMembersFull = (Get-JDMsolGroupMember -ObjectId $GroupIDFull -Recursive).EmailAddress
    $GroupMembersBasic = (Get-JDMsolGroupMember -ObjectId $GroupIDBasic -Recursive).EmailAddress
    Write-Output "- GroupMembers Full: $GroupMembersFull"
    Write-Output "- GroupMembers Basic: $GroupMembersBasic"
    Write-Output ""
    Write-Output "Checking for changes..."
    $GroupMembers = $Null
	If (($GroupMembersFull) -and ($GroupMembersBasic)){
		$GroupMemberCompare = Compare-Object -ReferenceObject $GroupMembersFull -DIfferenceObject $GroupMembersBasic -includeEqual -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
		$GroupMembers = $GroupMemberCompare.InputObject
	} Else {
        If ($GroupMembersFull) {
		    $GroupMembers = $GroupMembersFull
        }
        If ($GroupMembersBasic){
		    $GroupMembers = $GroupMembersBasic
        }
	}
	
    #Get all already licensed users in current scope
    $ActiveUsers = ($LicensedUserDetails | Where-Object {$_.Licenses.LicenseName -eq $LicenseSKU}).UserPrincipalName
    $UsersToHandle = $null
    $UsersToDelete = $null
    $UsersToChange = @()
	If ($GroupMembers -ne $Null) {
		If ($ActiveUsers) {
			#Compare $Groupmembers and $Activeusers
			#Users which are in the group but not licensed, will be added
			#Users licensed, but not, will be evaluated for deletion or change of license
			$UsersToHandle = Compare-Object -ReferenceObject $GroupMembers -DifferenceObject $ActiveUsers -IncludeEqual -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $UsersAlreadyMember = ($UsersToHandle | Where-Object {$_.SideIndicator -eq '=='}).InputObject
            If ($UsersAlreadyMember) {Write-Output "- Already member: $UsersAlreadyMember"}
			$UsersToAdd = ($UsersToHandle | Where-Object {$_.SideIndicator -eq '<='}).InputObject
			If ($UsersToAdd) {Write-Output "- New Members: $UsersToAdd"}
			$UsersToDelete = ($UsersToHandle | Where-Object {$_.SideIndicator -eq '=>'}).InputObject
			If ($UsersToDelete) {Write-Output "- Remove members: $UsersToDelete"}
			Foreach ($ActiveUser in $UsersAlreadyMember){
				$UserEnabledPlans = (($LicensedUserDetails | Where-Object {$_.UserPrincipalName -eq $ActiveUser}).Licenses|Where-Object {$_.LicenseName -eq $LicenseSKU}).EnabledPlans
				$UserDisabledPlans = (($LicensedUserDetails | Where-Object {$_.UserPrincipalName -eq $ActiveUser}).Licenses|Where-Object {$_.LicenseName -eq $LicenseSKU}).DisabledPlans
                If ($GroupMembersFull -contains $ActiveUser){
                    If ($UserDisabledPlans -ne $Null){
                        $MissingUserEnabledPlans = @()
                        ForEach ($MissingUserEnabledPlan in $UserDisabledPlans){
                            If ($UserEnabledPlans -notcontains $MissingUserEnabledPlan){
                                $MissingUserEnabledPlans += $MissingUserEnabledPlan
                            }
                        }
                        If($MissingUserEnabledPlans -ne $Null){
                            Write-Output "- Correction Member (Full): $ActiveUser"
                            Write-Output "-- Disabled Plans: $UserDisabledPlans"
                            Write-Output "-- Missing Plans: $MissingUserEnabledPlans"
                            $UsersToChange += $ActiveUser
                        }
                    }
                }
                Else {
				    If ($UserEnabledPlans -ne $Null){
                        $CompareUserEnabledPlans = (Compare-Object -ReferenceObject $UserEnabledPlans -DifferenceObject $EnabledPlans -IncludeEqual -ErrorAction SilentlyContinue -WarningAction SilentlyContinue| Where-Object {$_.SideIndicator -eq '<='}).InputObject
                        If ($CompareUserEnabledPlans -ne $Null){
                            $NotAllowedUserEnabledPlans = @()
                            ForEach ($NotAllowedUserEnabledPlan in $CompareUserEnabledPlans){
                                If ($UserDisabledPlans -notcontains $NotAllowedUserEnabledPlan){
                                    $NotAllowedUserEnabledPlans += $NotAllowedUserEnabledPlan
                                }
                            }
                            If($NotAllowedUserEnabledPlans -ne $Null){
                                Write-Output "- Correction Member (Basic): $ActiveUser"
                                Write-Output "-- Enabled Plans: $UserEnabledPlans"
                                Write-Output "-- Not allowed Plans: $NotAllowedUserEnabledPlans"
                                $UsersToChange += $ActiveUser
                            }
                        }
				    }
				    If ($UserDisabledPlans -ne $Null){
                        $CompareUserDisabledPlans = (Compare-Object -ReferenceObject $UserDisabledPlans -DifferenceObject $EnabledPlans -IncludeEqual -ErrorAction SilentlyContinue -WarningAction SilentlyContinue| Where-Object {$_.SideIndicator -eq '=='}).InputObject
                        If ($CompareUserDisabledPlans -ne $Null){
                            $MissingUserEnabledPlans = $CompareUserDisabledPlans
                            Write-Output "- Correction Member (Basic): $ActiveUser"
                            Write-Output "-- Disabled Plans: $UserDisabledPlans"
                            Write-Output "-- Missing Plans: $MissingUserEnabledPlans"
                            $UsersToChange += $ActiveUser
                        }
                    }
				}
			}
		} Else {
			#No licenses currently assigned for the license in scope, assign licenses to all group members.
			$UsersToAdd = $GroupMembers
			If ($UsersToAdd) {Write-Output "- New Members: $UsersToAdd"}
		}
	} Else {
		If ($ActiveUsers){
			Write-Warning   "- WARNING: Group $GroupNameBasic and $GroupNameFull both are empty - will process removal or move of all users with license $($AccountSKU.AccountSkuId)"
            $SendEmail = $True
            $EmailBody += ("- WARNING: Group $GroupNameBasic and $GroupNameFull both are empty - will process removal or move of all users with license $($AccountSKU.AccountSkuId)" + "`r`n")
			#If no users are a member in the group, add them for deletion or change of license.
			$UsersToDelete = $ActiveUsers
			Write-Output "- Remove members: $UsersToDelete"
		} Else {
            Write-Output "- Group $GroupNameBasic and $GroupNameFull both are empty."
        }
	}
    Write-Output ""

    #Change members plans
    If ($UsersToChange -ne $Null) {
        Write-Output "Processing changing member serviceplans..."
        Foreach ($User in $UsersToChange) {
			If ($User -ne $Null) { 
                Write-Output "- $User plans are not correct, changing..."
				try {
					$LicenseConfig = @{
						UserPrincipalName = $User
						AddLicenses = $AccountSKU.AccountSkuId
					}
					If ($GroupMembersFull -notcontains $User){
						If ($EnabledPlans) {
							$LicenseConfig['LicenseOptions'] = $LicenseOptions
						}
					}
                    Set-MsolUserLicense -UserPrincipalName $User -RemoveLicenses $AccountSKU.AccountSkuId -ErrorAction Stop -WarningAction Stop
					Set-MsolUserLicense @LicenseConfig -ErrorAction Stop -WarningAction Stop
					Write-Output "-- SUCCESS: Changed $LicenseSKU for $User"
				} catch {
					Write-Warning "-- WARNING: Error when changing plans on user $User"
                    $SendEmail = $True
                    $EmailBody += ("- WARNING: Error when changing plans on user $User" + "`r`n")
				}
            }
        }
        $UsersToChange = $Null
        Write-Output ""
	}
    
    #Remove license members...
	If ($UsersToDelete -ne $Null) {
        Write-Output "Processing removing members..."
		Foreach ($User in $UsersToDelete) {
			If ($User -ne $Null) { 
				#The user is no longer a member of license group, remove license
				Write-Warning "- $User is not a member of group $GroupNameBasic or $GroupNameFull, license will be removed... "
				try {
					Set-MsolUserLicense -UserPrincipalName $User -RemoveLicenses $AccountSKU.AccountSkuId -ErrorAction Stop -WarningAction Stop
					Write-Output "-- SUCCESS: Removed $LicenseSKU for $User"
				} catch {
					Write-Warning "-- WARNING: Error when removing license on user $User"
                    $SendEmail = $True
                    $EmailBody += ("- WARNING: Error when removing license on user $User" + "`r`n")
				}
			}
		}
        $UsersToDelete = $Null
        Write-Output ""
	}
    
    #Process Add license members...
	If ($UsersToAdd) {
        Write-Output "Processing adding members..."
        #Check the amount of licenses left...
        If ($AccountSKU.ActiveUnits - $AccountSKU.consumedunits -lt $UsersToAdd.Count) {
            Write-Warning '- WARNING: Not enough licenses for all users, please remove user licenses or buy more licenses of' $LicenseSKU
            $SendEmail = $True
            $EmailBody += ("- WARNING: Not enough licenses for all users, please remove user licenses or buy more licenses of $LicenseSKU" + "`r`n")
        }Else{
            #Add new license members...
	        Foreach ($User in $UsersToAdd){
		        If ($user -ne $null) {
                Write-Output "- $User missing $LicenseSKU license, adding..."
		        #Process all users for license assignment, If not already licensed with the SKU in order.
			        If ((Get-MsolUser -UserPrincipalName $User).Licenses.AccountSkuId -notcontains $AccountSku.AccountSkuId) {
				        try {
						    #Assign UsageLocation and License.
        					Set-MsolUser -UserPrincipalName $User -UsageLocation $UsageLocation -ErrorAction Stop -WarningAction Stop
					        $LicenseConfig = @{
						        UserPrincipalName = $User
						        AddLicenses = $AccountSKU.AccountSkuId
					        }
					        If ($GroupMembersFull -notcontains $User){
						        If ($EnabledPlans) {
							        $LicenseConfig['LicenseOptions'] = $LicenseOptions
						        }
					        }
        					Set-MsolUserLicense @LicenseConfig -ErrorAction Stop -WarningAction Stop
					        Write-Output "-- SUCCESS: Licensed $User with $LicenseSKU"
				        } catch {
					        Write-Warning "-- WARNING: Error when licensing $User"
                            $SendEmail = $True
                            $EmailBody += ("- WARNING: Error when licensing $User" + "`r`n")
				        }
			        }
		        }
	        }
        }
        $UsersToAdd = $Null
        Write-Output ""
    }
    Write-Output "--------------------------------------------------------------------------"
}
Write-Output "**************************** Stop Logging ********************************"
If ($SendEmail){
    If ($EmailCred){
        Send-MailMessage -To $EmailTo -from $EmailFrom -subject $EmailSubject -body $EmailBody -smtpServer $SMTPServer -Attachments $LogFile.path -Port $SMTPPort -Credential $EmailCred
    }Else{
        Send-MailMessage -To $EmailTo -from $EmailFrom -subject $EmailSubject -body $EmailBody -smtpServer $SMTPServer -Attachments $LogFile.path -Port $SMTPPort
    }
}
$LogFile | Disable-LogFile
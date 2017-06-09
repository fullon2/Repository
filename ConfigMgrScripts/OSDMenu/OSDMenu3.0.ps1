<# 
.SYNOPSIS 
Displays a GUI usable in a SCCM OSD Task Sequence based on XML file.   
.DESCRIPTION
Displays a GUI usable in a SCCM OSD Task Sequence based on XML file.
Create GUI options in OSDMenu.xml  
.PARAMETER XMLFile
File path to a XML File to be used for building GUI.
.PARAMETER DemoMode
Just display the output, no changes are made.
.EXAMPLE 
powershell -executionpolicy Bypass -file .\OSDMenu.ps1 -XMLFile .\OSDMenu.xml
.NOTES
Sander Schouten (sander.schouten@proactvx.com)

Copyright ProactVX B.V, All Rights reserved.  
#> 

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true, HelpMessage="Specificeer de XML input file")]
	[ValidateNotNullOrEmpty()]
    [string]$XMLFile,
    [boolean]$DemoMode
)

## Combine Form info
Function Load-Form 
{
    $Form.Size = New-Object System.Drawing.Size($OSDMenuWidth,$OSDMenuMaxHeight)
    $Form.Controls.AddRange($FormItems)
    $Form.Add_Shown({$Form.Activate()})
    [void] $Form.ShowDialog()
}

## Retreive TS variable value from ConfigMgr properties
Function Get-TSVariableValue ($TSVariable) 
{
    If ($DemoMode -eq $true){
        $TSVariableValue = "demo"
    }
    Else {
        $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
        $TSVariableValue = $TSEnv.Value($TSVariable)
        If (($TSVariableValue -eq $Null) -or ($TSVariableValue.ToUpper() -like '*MININT-*')){
            $TSVariableValue = ""
        }
    }
    $TSVariableValue
}

## Set TS variable value to ConfigMgr properties
Function Set-TSVariableValue ($TSVariable, $TSVariableValue) 
{
    $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $TSEnv.Value($TSVariable) = $TSVariableValue
}

## Enable checked options to ConfigMgr properties
Function Enable-CheckedOptions
{
    $ErrorCount = 0
    $DemoModeItems = @()
    Foreach ($FormItem in $FormItems) {
        If ($FormItem.AccessibilityObject.Role -eq "CheckButton") {
            If ($FormItem.Checked -eq $True) {
                If ($DemoMode -eq $true){
                    $DemoModeItem= @{name = $FormItem.Name;value = "true"}
                    $DemoModeItems += $DemoModeItem
                }
                Else {
                    Set-TSVariableValue -TSVariable $FormItem.Name -TSVariableValue "true"
                }
            }
        }
        ElseIf ($FormItem.AccessibilityObject.Role -eq "ComboBox") {
            If ($DemoMode -eq $true){
                $DemoModeItem= @{name = $FormItem.Name;value = $FormItem.SelectedItem.ToString().Tolower()}
                $DemoModeItems += $DemoModeItem
            }
            Else {
                Set-TSVariableValue -TSVariable $FormItem.Name -TSVariableValue $FormItem.SelectedItem.ToString().Tolower()
            }
        }
        ElseIf ($FormItem.AccessibilityObject.Role -eq "Text") {
            $ErrorProvider.Clear()
            If ($FormItem.Text -match $FormItem.Tag) {
                If ($DemoMode -eq $true){
                    $DemoModeItem= @{name = $FormItem.Name;value = $FormItem.Text.ToUpper()}
                    $DemoModeItems += $DemoModeItem
                }
                Else {
                    Set-TSVariableValue -TSVariable $FormItem.Name -TSVariableValue $FormItem.Text.ToUpper()
                }
            }
            Else {
                $ErrorCount += 1
                $ErrorProvider.SetError($FormItem, "Veld is incorrect. Tip: Zie help voor informatie.")
            }
        }
    }
    If ($ErrorCount -eq 0) { 
        $Form.Close()
        If ($DemoMode -eq $true){
            Load-Demo $DemoModeItems
        }
    }
}
Function Load-Demo ($DemoModeItems)
{
    Add-Type -AssemblyName System.Windows.Forms 
    $LabelHeight = 20
    $Label = New-Object System.Windows.Forms.Label
    $Label.Location = New-Object System.Drawing.Size(12,20)
    foreach($DemoModeItem in $DemoModeItems){
        $labelText += ("TSVariable: " + $DemoModeItem.name + "   - Value: " + $DemoModeItem.value + "`n")
        $LabelHeight += 12
    }
    $Label.Text = $labelText
    $Label.Size = New-Object System.Drawing.Size(255,$LabelHeight)
    $Label.Font = "Ariel,8"

    $KaderHeight = ($LabelHeight + 20)
    $Kader = New-Object System.Windows.Forms.GroupBox
    $Kader.Location = New-Object System.Drawing.Size(8,5)
    $Kader.Size = New-Object System.Drawing.Size(270,$KaderHeight)
    $Kader.Text = "Result"

    $ButtonLocationHeight = ($KaderHeight + 12)
    $Button = New-Object System.Windows.Forms.Button
    $Button.Location = New-Object System.Drawing.Size(120,$ButtonLocationHeight)
    $Button.Size = New-Object System.Drawing.Size(50,20)
    $Button.Text = "OK"
    $Button.Add_Click({$DemoForm.Close()})

    $DemoForm = New-Object system.Windows.Forms.Form
    $DemoForm.Text = "DemoMode"
    $DemoForm.StartPosition = "CenterScreen"
    $DemoForm.SizeGripStyle = "Hide"
    $DemoForm.ControlBox = $false
    $DemoForm.TopMost = $true
    $DemoFormHeight = ($KaderHeight + 80)
    $DemoForm.Size = New-Object System.Drawing.Size(302,$DemoFormHeight)

    $DemoForm.Controls.Add($Button)
    $DemoForm.Controls.Add($Label)
    $DemoForm.Controls.Add($Kader)
    $DemoForm.ShowDialog()
}

## Exit Form with error (Cancel)
Function Cancel-Form
{
    If ($DemoMode -eq $true){
        $Form.Close()
    }
    Else {
        $Form.Close()
	    wpeutil.exe shutdown
    }
}

Function Display-help
{
    Add-Type -AssemblyName System.Windows.Forms 
    $LabelHeight = 20
    $Label = New-Object System.Windows.Forms.Label
    $Label.Location = New-Object System.Drawing.Size(12,20)
    $LabelTekst = Get-Content("OSDMenuHelp.txt")
    $Label.Text = foreach($line in $labelTekst){"$line `n"; $LabelHeight += 12}
    $Label.Size = New-Object System.Drawing.Size(255,$LabelHeight)
    $Label.Font = "Ariel,7"

    $KaderHeight = ($LabelHeight + 20)
    $Kader = New-Object System.Windows.Forms.GroupBox
    $Kader.Location = New-Object System.Drawing.Size(8,5)
    $Kader.Size = New-Object System.Drawing.Size(270,$KaderHeight)
    $Kader.Text = "Help"

    $ButtonLocationHeight = ($KaderHeight + 12)
    $Button = New-Object System.Windows.Forms.Button
    $Button.Location = New-Object System.Drawing.Size(120,$ButtonLocationHeight)
    $Button.Size = New-Object System.Drawing.Size(50,20)
    $Button.Text = "OK"
    $Button.Add_Click({$HelpForm.Close()})

    $HelpForm = New-Object system.Windows.Forms.Form
    $HelpForm.Text = "Help OSD Menu"
    $HelpForm.StartPosition = "CenterScreen"
    $HelpForm.SizeGripStyle = "Hide"
    $HelpForm.ControlBox = $false
    $HelpForm.TopMost = $true
    $HelpFormHeight = ($KaderHeight + 80)
    $HelpForm.Size = New-Object System.Drawing.Size(302,$HelpFormHeight)

    $HelpForm.Controls.Add($Button)
    $HelpForm.Controls.Add($Label)
    $HelpForm.Controls.Add($Kader)
    $HelpForm.ShowDialog()
}

##### Start Main script #######

## Create Form basiscs
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
$Global:ErrorProvider = New-Object System.Windows.Forms.ErrorProvider

## Load Form input XML
[xml]$XMLOSDMenu = Get-Content -Path $XMLFile

## Set base values
$TabIndex = 0
$OSDMenuWidth = 272
$OSDMenuMinHeight = 105
$OSDMenuMaxHeight = $OSDMenuMinHeight
$ChBHeight = 20
$CBHeight = 20
$TBHeight = 50
$GBLocationTop = 10
$xBLocationTop = 30
$FormItems = @()
 
## Create base form layout
$Form = New-Object System.Windows.Forms.Form    
$Form.MinimumSize = New-Object System.Drawing.Size($OSDMenuWidth,$OSDMenuMinHeight)
$Form.StartPosition = "CenterScreen"
$Form.SizeGripStyle = "Hide"
$Form.Text = ($XMLOSDMenu.OSDMenu.Name + " " + $XMLOSDMenu.OSDMenu.Version)
$Form.ControlBox = $false
$Form.TopMost = $true
$Icon = [system.drawing.icon]::ExtractAssociatedIcon($PSHOME + "\powershell.exe")
$Form.Icon = $Icon
$Form.Opacity = 0.9

## Build Form Items
ForEach ($Groupbox in $XMLOSDMenu.OSDMenu.GroupBox){
    If ($Groupbox.enabled -eq 1){
        $GBEntry = New-Object System.Windows.Forms.GroupBox
        $GBEntry.Location = New-Object System.Drawing.Size(15,$GBLocationTop)
        $GBEntry.Text = $Groupbox.name
        $xBLocationTop = ($GBLocationTop + 20)
        If ($Groupbox.type -eq "TextBox"){
            $GBHeight = 5
            $TBEntry = New-Object System.Windows.Forms.TextBox
            $TBEntry.Location = New-Object System.Drawing.Size(30,$xBLocationTop)
            $TBEntry.Size = New-Object System.Drawing.Size(195,$TBHeight)
            $TBEntry.Text = Get-TSVariableValue -TSVariable $Groupbox.rvariablename
            $TBEntry.Name = $Groupbox.wvariablename
            $TBEntry.Tag = $Groupbox.match
            $TBEntry.TabIndex = ($TabIndex += 1)
            $FormItems += $TBEntry
            $GBHeight += $TBHeight
            $xBLocationTop += $TBHeight
        }
        ElseIf ($Groupbox.type -eq "CheckBox"){
            $GBHeight = 30
            ForEach ($CheckBox in $Groupbox.CheckBox){
                If ($CheckBox.enabled -eq 1){
                    $ChBEntry = new-object System.Windows.Forms.checkbox
                    $ChBEntry.Location = new-object System.Drawing.Size(30,$xBLocationTop)
                    $ChBEntry.Size = new-object System.Drawing.Size(195,$ChBHeight)
                    $ChBEntry.Text = $CheckBox.Text
                    $ChBEntry.Name = $CheckBox.variablename
                    $ChBEntry.Checked = $CheckBox.Checked
                    $ChBEntry.TabIndex = ($TabIndex += 1)
                    $FormItems += $ChBEntry
                    $GBHeight += $ChBHeight
                    $xBLocationTop += $ChBHeight
                }
            }
        }
        ElseIf ($Groupbox.type -eq "ComboBox"){
            $GBHeight = 35
            ForEach ($ComboBox in $Groupbox.ComboBox){
                $CBEntry = new-object System.Windows.Forms.ComboBox
                $CBEntry.Location = new-object System.Drawing.Size(30,$xBLocationTop)
                $CBEntry.Size = new-object System.Drawing.Size(195,$CBHeight)
                $CBEntry.DropDownStyle = "DropDownList"
                $CBEntry.TabIndex = ($TabIndex += 1)
                $CBEntry.Name = $ComboBox.variablename
                $CBEntry.Items.AddRange(@($ComboBox.ComboBoxItem.text))
                $CurrentVariableValue = Get-TSVariableValue -TSVariable $ComboBox.variablename
                $CBEntry.SelectedIndex = 0
                ForEach ($ComboBoxItem in $ComboBox.ComboBoxItem){
                    If ($ComboBoxItem.variablevalue.ToLower() -eq $CurrentVariableValue.ToLower()){ 
                        $CBEntry.SelectedIndex = $ComboBoxItem.id
                    }
                }
                $FormItems += $CBEntry
                $GBHeight += $CBHeight
                $xBLocationTop += $CBHeight
            }
        }
        $GBLocationTop += $GBHeight
        $GBEntry.Size = New-Object System.Drawing.Size(225,$GBHeight)
        $OSDMenuMaxHeight += $GBHeight
        $FormItems += $GBEntry
    }
}

## Create buttons
$ButtonHeight = (($OSDMenuMaxHeight - $OSDMenuMinHeight) + 17)
$ButtonOK = New-Object System.Windows.Forms.Button
$ButtonOK.Location = New-Object System.Drawing.Size(185,$ButtonHeight)
$ButtonOK.Size = New-Object System.Drawing.Size(50,20)
$ButtonOK.Text = "OK"
$ButtonOK.TabIndex = ($TabIndex += 1)
$ButtonOK.Add_Click({Enable-CheckedOptions})
$FormItems += $ButtonOK

$ButtonCancel = New-Object System.Windows.Forms.Button
$ButtonCancel.Location = New-Object System.Drawing.Size(20,$ButtonHeight)
$ButtonCancel.Size = New-Object System.Drawing.Size(50,20)
$ButtonCancel.Text = "Cancel"
$ButtonCancel.TabIndex = ($TabIndex += 1)
$ButtonCancel.Add_Click({Cancel-Form})
$FormItems += $ButtonCancel

If($XMLOSDMenu.OSDMenu.enablehelp -eq 1){
    $ButtonHelp = New-Object System.Windows.Forms.Button
    $ButtonHelp.Location = New-Object System.Drawing.Size(102,$ButtonHeight)
    $ButtonHelp.Size = New-Object System.Drawing.Size(50,20)
    $ButtonHelp.Text = "Help"
    $ButtonHelp.TabIndex = ($TabIndex += 1)
    $ButtonHelp.Add_Click({Display-help})
    $FormItems += $ButtonHelp
}

## Status Bar Label
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
[void]$statusStrip.Items.Add($statusLabel)
$statusStrip.SizingGrip = $false
$statusLabel.AutoSize = $true
$statusLabel.Text = [char]0x00A9 + " 2016 ProactVX B.V."
$FormItems += $statusStrip

## Create Enter properties
$Form.KeyPreview = $True
$Form.Add_KeyDown({if ($_.KeyCode -eq "Enter"){Enable-CheckedOptions}})

## Load complete form
Load-Form

#Sander Schouten, ProactVX
function Test-DAConnectionStatus
{
 $ErrorActionPreference = "SilentlyContinue"
 if ((Get-DAConnectionStatus).status -eq 'ConnectedRemotely'){
    return $True
 }
 Else {
    return $False
 }
} 
Test-DAConnectionStatus
$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
$tsenv.Value('ConnectedRemotely') = Test-DAConnectionStatus

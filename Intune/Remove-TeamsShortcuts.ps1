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
 Remove Teams shortcuts continuously.    

.DESCRIPTION 
 Remove Teams shortcuts continuously.

.PARAMETER Company
 Name of Company script is used for. Used for logging folders

#> 

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)] [String] $Company = "Intune-Powershell-Scripts"
)


$scriptName = "Remove-TeamsShortcuts"
if (-not (Test-Path "$($env:ProgramData)\$Company\$scriptName"))
{
    Mkdir "$($env:ProgramData)\$Company\$scriptName"
}
# Create a tag file just so Intune knows this was installed
Set-Content -Path "$($env:ProgramData)\$Company\$scriptName\$scriptName.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\$Company\$scriptName\$scriptName.log"

function executeAsLoggedOnUser ($Command,$Hidden=$true) {
    # custom API for token manipulation, allowing the system account to execute a command as the currently logged-on user.
    # C# borrowed from the awesome Justin Myrray (https://github.com/murrayju/CreateProcessAsUser)

$csharpCode = @"
    using System;  
    using System.Runtime.InteropServices;

    namespace murrayju.ProcessExtensions  
    {
        public static class ProcessExtensions
        {
            #region Win32 Constants

            private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
            private const int CREATE_NO_WINDOW = 0x08000000;

            private const int CREATE_NEW_CONSOLE = 0x00000010;

            private const uint INVALID_SESSION_ID = 0xFFFFFFFF;
            private static readonly IntPtr WTS_CURRENT_SERVER_HANDLE = IntPtr.Zero;

            #endregion

            #region DllImports

            [DllImport("advapi32.dll", EntryPoint = "CreateProcessAsUser", SetLastError = true, CharSet = CharSet.Ansi, CallingConvention = CallingConvention.StdCall)]
            private static extern bool CreateProcessAsUser(
                IntPtr hToken,
                String lpApplicationName,
                String lpCommandLine,
                IntPtr lpProcessAttributes,
                IntPtr lpThreadAttributes,
                bool bInheritHandle,
                uint dwCreationFlags,
                IntPtr lpEnvironment,
                String lpCurrentDirectory,
                ref STARTUPINFO lpStartupInfo,
                out PROCESS_INFORMATION lpProcessInformation);

            [DllImport("advapi32.dll", EntryPoint = "DuplicateTokenEx")]
            private static extern bool DuplicateTokenEx(
                IntPtr ExistingTokenHandle,
                uint dwDesiredAccess,
                IntPtr lpThreadAttributes,
                int TokenType,
                int ImpersonationLevel,
                ref IntPtr DuplicateTokenHandle);

            [DllImport("userenv.dll", SetLastError = true)]
            private static extern bool CreateEnvironmentBlock(ref IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

            [DllImport("userenv.dll", SetLastError = true)]
            [return: MarshalAs(UnmanagedType.Bool)]
            private static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool CloseHandle(IntPtr hSnapshot);

            [DllImport("kernel32.dll")]
            private static extern uint WTSGetActiveConsoleSessionId();

            [DllImport("Wtsapi32.dll")]
            private static extern uint WTSQueryUserToken(uint SessionId, ref IntPtr phToken);

            [DllImport("wtsapi32.dll", SetLastError = true)]
            private static extern int WTSEnumerateSessions(
                IntPtr hServer,
                int Reserved,
                int Version,
                ref IntPtr ppSessionInfo,
                ref int pCount);

            #endregion

            #region Win32 Structs

            private enum SW
            {
                SW_HIDE = 0,
                SW_SHOWNORMAL = 1,
                SW_NORMAL = 1,
                SW_SHOWMINIMIZED = 2,
                SW_SHOWMAXIMIZED = 3,
                SW_MAXIMIZE = 3,
                SW_SHOWNOACTIVATE = 4,
                SW_SHOW = 5,
                SW_MINIMIZE = 6,
                SW_SHOWMINNOACTIVE = 7,
                SW_SHOWNA = 8,
                SW_RESTORE = 9,
                SW_SHOWDEFAULT = 10,
                SW_MAX = 10
            }

            private enum WTS_CONNECTSTATE_CLASS
            {
                WTSActive,
                WTSConnected,
                WTSConnectQuery,
                WTSShadow,
                WTSDisconnected,
                WTSIdle,
                WTSListen,
                WTSReset,
                WTSDown,
                WTSInit
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct PROCESS_INFORMATION
            {
                public IntPtr hProcess;
                public IntPtr hThread;
                public uint dwProcessId;
                public uint dwThreadId;
            }

            private enum SECURITY_IMPERSONATION_LEVEL
            {
                SecurityAnonymous = 0,
                SecurityIdentification = 1,
                SecurityImpersonation = 2,
                SecurityDelegation = 3,
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct STARTUPINFO
            {
                public int cb;
                public String lpReserved;
                public String lpDesktop;
                public String lpTitle;
                public uint dwX;
                public uint dwY;
                public uint dwXSize;
                public uint dwYSize;
                public uint dwXCountChars;
                public uint dwYCountChars;
                public uint dwFillAttribute;
                public uint dwFlags;
                public short wShowWindow;
                public short cbReserved2;
                public IntPtr lpReserved2;
                public IntPtr hStdInput;
                public IntPtr hStdOutput;
                public IntPtr hStdError;
            }

            private enum TOKEN_TYPE
            {
                TokenPrimary = 1,
                TokenImpersonation = 2
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct WTS_SESSION_INFO
            {
                public readonly UInt32 SessionID;

                [MarshalAs(UnmanagedType.LPStr)]
                public readonly String pWinStationName;

                public readonly WTS_CONNECTSTATE_CLASS State;
            }

            #endregion

            // Gets the user token from the currently active session
            private static bool GetSessionUserToken(ref IntPtr phUserToken)
            {
                var bResult = false;
                var hImpersonationToken = IntPtr.Zero;
                var activeSessionId = INVALID_SESSION_ID;
                var pSessionInfo = IntPtr.Zero;
                var sessionCount = 0;

                // Get a handle to the user access token for the current active session.
                if (WTSEnumerateSessions(WTS_CURRENT_SERVER_HANDLE, 0, 1, ref pSessionInfo, ref sessionCount) != 0)
                {
                    var arrayElementSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                    var current = pSessionInfo;

                    for (var i = 0; i < sessionCount; i++)
                    {
                        var si = (WTS_SESSION_INFO)Marshal.PtrToStructure((IntPtr)current, typeof(WTS_SESSION_INFO));
                        current += arrayElementSize;

                        if (si.State == WTS_CONNECTSTATE_CLASS.WTSActive)
                        {
                            activeSessionId = si.SessionID;
                        }
                    }
                }

                // If enumerating did not work, fall back to the old method
                if (activeSessionId == INVALID_SESSION_ID)
                {
                    activeSessionId = WTSGetActiveConsoleSessionId();
                }

                if (WTSQueryUserToken(activeSessionId, ref hImpersonationToken) != 0)
                {
                    // Convert the impersonation token to a primary token
                    bResult = DuplicateTokenEx(hImpersonationToken, 0, IntPtr.Zero,
                        (int)SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation, (int)TOKEN_TYPE.TokenPrimary,
                        ref phUserToken);

                    CloseHandle(hImpersonationToken);
                }

                return bResult;
            }

            public static bool StartProcessAsCurrentUser(string cmdLine, bool visible, string appPath = null, string workDir = null)
            {
                var hUserToken = IntPtr.Zero;
                var startInfo = new STARTUPINFO();
                var procInfo = new PROCESS_INFORMATION();
                var pEnv = IntPtr.Zero;
                int iResultOfCreateProcessAsUser;

                startInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));

                try
                {
                    if (!GetSessionUserToken(ref hUserToken))
                    {
                        throw new Exception("StartProcessAsCurrentUser: GetSessionUserToken failed.");
                    }

                    uint dwCreationFlags = CREATE_UNICODE_ENVIRONMENT | (uint)(visible ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW);
                    startInfo.wShowWindow = (short)(visible ? SW.SW_SHOW : SW.SW_HIDE);
                    startInfo.lpDesktop = "winsta0\\default";

                    if (!CreateEnvironmentBlock(ref pEnv, hUserToken, false))
                    {
                        throw new Exception("StartProcessAsCurrentUser: CreateEnvironmentBlock failed.");
                    }

                    if (!CreateProcessAsUser(hUserToken,
                        appPath, // Application Name
                        cmdLine, // Command Line
                        IntPtr.Zero,
                        IntPtr.Zero,
                        false,
                        dwCreationFlags,
                        pEnv,
                        workDir, // Working directory
                        ref startInfo,
                        out procInfo))
                    {
                        throw new Exception("StartProcessAsCurrentUser: CreateProcessAsUser failed.\n");
                    }

                    iResultOfCreateProcessAsUser = Marshal.GetLastWin32Error();
                }
                finally
                {
                    CloseHandle(hUserToken);
                    if (pEnv != IntPtr.Zero)
                    {
                        DestroyEnvironmentBlock(pEnv);
                    }
                    CloseHandle(procInfo.hThread);
                    CloseHandle(procInfo.hProcess);
                }
                return true;
            }
        }
    }
"@
    # Importing the source code as csharp
    $compilerParams = [System.CodeDom.Compiler.CompilerParameters]::new()
    $compilerParams.ReferencedAssemblies.AddRange(('System.Runtime.InteropServices.dll', 'System.dll'))
    $compilerParams.CompilerOptions = '/unsafe'
    $compilerParams.GenerateInMemory = $True
    Add-Type -TypeDefinition $csharpCode -Language CSharp -CompilerParameters $compilerParams
    # Execute a process as the currently logged on user. 
    # Absolute paths required if running as SYSTEM!
    if($Hidden) {
        $runCommand = [murrayju.ProcessExtensions.ProcessExtensions]::StartProcessAsCurrentUser($Command,$false)
    }else{
        $runCommand = [murrayju.ProcessExtensions.ProcessExtensions]::StartProcessAsCurrentUser($Command,$true)
    }

    if ($runCommand) {
        return "Executed `"$Command`" as loggedon user"
    } else {
        throw "Something went wrong when executing process as currently logged-on user"
    }
}

# Execute section

try {

    # lets output a test to the currently logged in users temp folder, outputting the users name.
    # You can go have a look in there to see that this works as expected

    $executeAsLoggedOnUserLog = "$($env:ProgramData)\$Company\$scriptName\$scriptName-AsUser.log"

$scriptFile = @'
start-transcript "{0}";
Start-Sleep -Seconds 3;
$DesktopPath = [Environment]::GetFolderPath("Desktop");
remove-item -path $DesktopPath\* -filter "Microsoft Teams*.lnk";
Write-Output "Removed Teams Shortcuts"
Stop-Transcript;
'@ -f $executeAsLoggedOnUserLog

    If (!(test-path "C:\ProgramData\Intune-PowerShell-Logs\temp")){$dummy = new-item -ItemType Directory -Force "C:\ProgramData\Intune-PowerShell-Logs\temp"}
    $scriptFile | Out-File  "C:\ProgramData\Intune-PowerShell-Logs\temp\executeAsLoggedOnUser.ps1" -force
    $userCommand = '{0}\System32\WindowsPowerShell\v1.0\powershell.exe -executionPolicy bypass -file C:\ProgramData\Intune-PowerShell-Logs\temp\executeAsLoggedOnUser.ps1' -f $($env:windir)
    # running command as logged-on user, and escaping backslashes so they get interpreted literaly
    executeAsLoggedOnUser -Command $userCommand.Replace("\","\\") -Hidden $True
    Sleep -s 1
    Remove-Item -Path "C:\ProgramData\Intune-PowerShell-Logs\temp\executeAsLoggedOnUser.ps1" -Force

} finally {
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


<#
.DISCLAIMER
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

.LICENSE
Copyright (c) Microsoft Corporation. All rights reserved.

.AUTHOR
patrick.shim@live.co.kr (Patrick Shim)

.VERSION
1.0.0.10 / 2022-03-30

.SYNOPSIS
Custom Script Extension to install applications and Windows Features on Windows VMs.

.DESCRIPTION
This script configures each VMs per the role of the VMs in a fully automated way. The script will install the following applications and Windows Features on the VMs: 
a. Common - PowerShell 7 and Az Modules 
b. 1 x AD Domain Controller - Active Directory Domain Services, DNS Server
c. 2 x Node Servers - Failover Clustering, File Server Services such as NFS, SMB, and iSCSI

.PARAMETER NodeList
An array that contains the VM names and IP addresses. It is passed as a parameter to the remote script.

.PARAMETER VmName
Specifies the name of the virtual machine.

.PARAMETER VmRole
Specifies the role of the virtual machine (`domain`, `domaincontroller`, or `dc` for a domain controller; anything else for a node).

.PARAMETER AdminName
Specifies the name of the administrator account for the domain.

.PARAMETER Secret
Specifies the password for the administrator account.

.PARAMETER DomainName
Specifies the name of the domain.

.PARAMETER DomainNetBiosName
Specifies the NetBIOS name of the domain.

.PARAMETER DomainServerIpAddress
Specifies the Private IP Address of the domain server.

.EXAMPLE
.\InstallRolesAndFeatures.ps1 -NodeList @(@("server-01", "192.168.1.1")) -VmRole domaincontroller -AdminName Admin -adminSecret P@ssw0rd -DomainName contoso.com -DomainNetBiosName CONTOSO -DomainServerIpAddress

.NOTES
- This script is tested on Windows Server 2022 VMs.
- This script requires elevated privileges to run, i.e., as an administrator.
- The `NodeList` parameter has default values for testing purposes.
- The `VmRole` parameter must be one of the following: `domain`, `domaincontroller`, or `dc` for a domain controller; anything else for a node.
- The `AdminName` and `-adminSecret` parameters must specify the name and password of an administrator account for the domain.
#>

param(
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $ResourceGroupName,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $VmRole,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $VmName,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $AdminName,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $Secret,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $DomainName,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $DomainNetBiosName,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $DomainServerIpAddress,
    [Parameter(Mandatory = $true)] [array]  [ValidateNotNullOrEmpty()] $NodeList,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $SaName,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $SaKey,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $ClusterName,
    [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $ClusterIp
)

Write-Output "ResourceGroupName: $ResourceGroupName"
Write-Output "VmRole: $VmRole"
Write-Output "VmName: $VmName"
Write-Output "AdminName: $AdminName"
Write-Output "DomainName: $DomainName"
Write-Output "DomainNetBiosName: $DomainNetBiosName"
Write-Output "DomainServerIpAddress: $DomainServerIpAddress"
Write-Output "NodeList: $NodeList"
Write-Output "SaName: $SaName"
Write-Output "SaKey: $SaKey"
Write-Output "ClusterName: $ClusterName"
Write-Output "ClusterIp: $ClusterIp"

############################################################################################################
# Variable Definitions
############################################################################################################

$tempPath = "C:\\Temp"
$msi = "PowerShell-7.3.2-win-x64.msi"
$msiPath = "$tempPath\\$msi"
$powershellUrl = "https://github.com/PowerShell/PowerShell/releases/download/v7.3.2/$msi"
$timeZone = "Singapore Standard Time"
$scriptUrl = "https://raw.githubusercontent.com/ms-apac-csu/mscs-storage-cluster/main/extensions/join-mscs-domain.ps1"
$scriptPath = "C:\\Temp\\join-mscs-domain.ps1"
$postConfigScriptUrl = "https://raw.githubusercontent.com/ms-apac-csu/mscs-storage-cluster/main/extensions/set-mscs-failover-cluster.ps1"
$postConfigScriptPath = "C:\\Temp\\set-mscs-failover-cluster.ps1"
$adminSecret = ConvertTo-SecureString -String $Secret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($AdminName, $adminSecret)

############################################################################################################
# Function Definitions
############################################################################################################

# Function to check if the VM has the specified Windows Feature installed.  Returns true if the feature is installed, false otherwise.
Function Test-WindowsFeatureInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FeatureName
    )

    $feature = Get-WindowsFeature -Name $FeatureName
    if ($feature.InstallState -ne "Installed") { 
        return $false 
    }
    else { 
        return $true 
    }
}

# Function to install specified Windows Features.
Function Install-RequiredWindowsFeatures {
    param(
        [Parameter(Mandatory = $true)] [System.Collections.Generic.List[string]] $FeatureList
    )
    
    $toInstallList = New-Object System.Collections.Generic.List[string]
    $features = Get-WindowsFeature $FeatureList -ErrorAction SilentlyContinue
    
    foreach ($feature in $features) {
        if ($feature.InstallState -ne 'Installed') { 
            # build a list of features to install
            $toInstallList.Add($feature.Name)
        }
    }

    if ($toInstallList.count -gt 0) {
        foreach ($feature in $toInstallList) {
            try {
                Install-WindowsFeature -Name $feature -IncludeManagementTools -IncludeAllSubFeature
                Write-EventLog -Message "Windows Feature $feature has been installed." `
                    -Source $eventSource `
                    -EventLogName $eventLogName `
                    -EntryType Information
            }
            catch {
                Write-EventLog -Message "An error occurred while installing Windows Feature $feature (Error: $($_.Exception.Message))." `
                    -Source $eventSource `
                    -EventLogName $eventLogName `
                    -EntryType Error
            }
        }
    }
    else {
        Write-EventLog -Message "Nothing to install. All required features are installed." `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Information
    }
}

# Function to check if PowerShell 7 is installed. If not, install it and install the Az module.
Function Install-PowerShellWithAzModules {
    param(
        [Parameter(Mandatory = $true)] [string] $Url,
        [Parameter(Mandatory = $true)] [string] $MsiPath
    )
    
    try {
        # check if a temp directory for a download exists. if not, create it.
        if (-not (Test-Path -Path $tempPath)) { 
            New-Item -Path $tempPath `
                -ItemType Directory `
                -Force 
        }
        
        # check if msi installer exists. if yes then skip the download and go to the installation.
        if (-not (Test-Path -Path $msiPath)) {
            Get-WebResourcesWithRetries -SourceUrl $url `
                -DestinationPath $msiPath
            
            Start-Process -FilePath msiexec.exe -ArgumentList "/i $msiPath /quiet /norestart /passive ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1" -Wait -ErrorAction SilentlyContinue
            
            Write-EventLog -Message "Installing PowerShell 7 completed." `
                -Source $eventSource `
                -EventLogName $eventLogName `
                -EntryType Information
        }
        else {
            # if msi installer exists, then just install in.
            Start-Process -FilePath msiexec.exe -ArgumentList "/i $Msi /quiet /norestart /passive ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1" -Wait -ErrorAction SilentlyContinue
            Write-EventLog -Message "Installing PowerShell 7 completed." `
                -Source $eventSource `
                -EventLogName $eventLogName `
                -EntryType Information
        }

        # contuning to install the Az modules.
        if ($null -eq (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet `
                -Force `
                -ErrorAction SilentlyContinue
        }
        else {
            Write-EventLog -Message "NuGet Package Provider is found. Skipping the installation." `
                -Source $eventSource `
                -EventLogName $eventLogName `
                -EntryType Information
        }
        
        Write-EventLog -Message "Installing the Az module." `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Information

        # Ensure the Az module is installed
        if ($null -eq (Get-Module -Name Az -ListAvailable -ErrorAction SilentlyContinue)) { 
            Install-Module -Name Az `
                -Force `
                -AllowClobber `
                -Scope AllUsers `
                -ErrorAction SilentlyContinue 
        
            Write-EventLog -Message "Az Modules have been installed." `
                -Source $eventSource `
                -EventLogName $eventLogName `
                -EntryType Information
        }
        else {
            Write-EventLog -Message "Az Modules are found. Skipping the installation." `
                -Source $eventSource `
                -EventLogName $eventLogName `
                -EntryType Information
        }

        # remove the AzureRM module if it exists
        if (Get-Module -ListAvailable -Name AzureRM) { 
            Uninstall-Module -Name AzureRM `
                -Force `
                -ErrorAction SilentlyContinue 
        }
    }
    catch {
        Write-EventLog -Message "Error installing PowerShell 7 with Az Modules (Error: $($_.Exception.Message))" `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Error
    }
}

# Function to download a file from a URL and retry if the download fails.
Function Get-WebResourcesWithRetries {
    param (
        [Parameter(Mandatory = $true)] [string] $SourceUrl,
        [Parameter(Mandatory = $true)] [string] $DestinationPath,
        [Parameter(Mandatory = $false)] [int] $MaxRetries = 5,
        [Parameter(Mandatory = $false)] [int] $RetryIntervalSeconds = 1
    )

    $retryCount = 0
    $completed = $false
    $response = $null

    while (-not $completed -and $retryCount -lt $MaxRetries) {
        try {
            $fileExists = Test-Path $DestinationPath
            $headers = @{}

            if ($fileExists) {
                $fileLength = (Get-Item $DestinationPath).Length
                $headers["Range"] = "bytes=$fileLength-"
            }

            $response = Invoke-WebRequest -Uri $SourceUrl `
                -Headers $headers `
                -OutFile $DestinationPath `
                -UseBasicParsing `
                -PassThru `
                -ErrorAction Stop

            if ($response.StatusCode -eq 206 -or $response.StatusCode -eq 200) { 
                $completed = $true 
            }
            else { 
                $retryCount++ 
            }
        }
        catch {
            $retryCount++
            Start-Sleep -Seconds (2 * $retryCount)
        }
    }

    if (-not $completed) { 
        Write-EventLog -Message "Failed to download file from $SourceUrl" `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Error
    } 

    else {
        Write-EventLog -Message "Download of $SourceUrl completed successfully" `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Information
    }
}

# Function to configure the domain controller.
Function Set-ADDomainServices {
    param(
        [Parameter(Mandatory = $true)]
        [string] $DomainName,
        [Parameter(Mandatory = $true)]
        [string] $DomainNetBiosName,
        [Parameter(Mandatory = $true)]
        [pscredential] $Credential
    )
    try {        
        Write-EventLog -Message 'Configuring Active Directory Domain Services...' `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Information

        Import-Module ADDSDeployment

        Install-ADDSForest -DomainName $DomainName `
            -DomainNetbiosName $DomainNetBiosName `
            -DomainMode 'WinThreshold' `
            -ForestMode 'WinThreshold' `
            -InstallDns `
            -SafeModeAdministratorPassword $Credential.Password `
            -Force

        Write-EventLog -Message 'Active Directory Domain Services has been configured.' `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType information
    }
    catch {
        Write-EventLog -Message "An error occurred while installing Active Directory Domain Services (Error: $($_.Exception.Message))" `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Error
    }
}

# Function to set extra VM configurations
Function Set-DefaultVmEnvironment {
    param(
        [Parameter(Mandatory = $true)] [string] $TempFolderPath,
        [Parameter(Mandatory = $true)] [string] $TimeZone
    )
    if (-not (Test-Path -Path $TempFolderPath)) { 
        New-Item -ItemType Directory -Path $TempFolderPath 
    }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0
    Set-TimeZone -Id $TimeZone
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
}

# Function to set the common Windows Firewall rules
Function Set-RequiredFirewallRules {
    param(
        [Parameter(Mandatory = $true)]
        [bool] $IsActiveDirectory
    )

    $ruleList = [System.Collections.ArrayList] @()
    
    $ruleList.Add(@(
            @{
                DisplayName = 'PowerShell Remoting'
                Direction   = 'Inbound'
                Protocol    = 'TCP'
                LocalPort   = @(5985, 5986)
                Enabled     = $true
            },
            @{
                DisplayName = 'ICMP'
                Direction   = 'Inbound'
                Protocol    = 'ICMPv4'
                Enabled     = $true
            },
            @{
                DisplayName = 'WinRM'
                Direction   = 'Inbound'
                Protocol    = 'TCP'
                LocalPort   = @(5985, 5986)
                Enabled     = $true
            }
        ))

    if ($IsActiveDirectory -eq $true) {
        $ruleList.Add(@(
                @{
                    DisplayName = 'DNS'
                    Direction   = 'Inbound'
                    Protocol    = 'UDP'
                    LocalPort   = 53
                    Enabled     = $true
                },
                @{
                    DisplayName = 'DNS'
                    Direction   = 'Inbound'
                    Protocol    = 'TCP'
                    LocalPort   = 53
                    Enabled     = $true
                },
                @{
                    DisplayName = 'Kerberos'
                    Direction   = 'Inbound'
                    Protocol    = 'UDP'
                    LocalPort   = 88
                    Enabled     = $true
                },
                @{
                    DisplayName = 'Kerberos'
                    Direction   = 'Inbound'
                    Protocol    = 'TCP'
                    LocalPort   = 88
                    Enabled     = $true
                }
            ))
    }
    else {
        $ruleList.Add(@(
                @{
                    DisplayName = 'SMB'
                    Direction   = 'Inbound'
                    Protocol    = 'TCP'
                    LocalPort   = 445
                    Enabled     = $true
                },
                @{
                    DisplayName = 'NFS'
                    Direction   = 'Inbound'
                    Protocol    = 'TCP'
                    LocalPort   = 2049
                    Enabled     = $true
                },
                @{
                    DisplayName = 'SQL Server'
                    Direction   = 'Inbound'
                    Protocol    = 'TCP'
                    LocalPort   = @(1433, 1434)
                    Enabled     = $true
                },
                @{
                    DisplayName = 'iSCSI Target Server'
                    Direction   = 'Inbound'
                    Protocol    = 'TCP'
                    LocalPort   = 3260
                    Enabled     = $true
                },
                @{
                    DisplayName = 'TFTP Server'
                    Direction   = 'Inbound'
                    Protocol    = 'UDP'
                    LocalPort   = 69
                    Enabled     = $true
                }
            ))
    }

    # Configure Windows Firewall
    $ruleList | ForEach-Object {
        $_ | ForEach-Object {
            $rule = $_
            $ruleName = $rule.DisplayName
            $ruleExists = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            if (-not $ruleExists) {
                $params = @{
                    DisplayName = $ruleName
                    Direction   = $rule.Direction
                    Protocol    = $rule.Protocol
                    Enabled     = if ($rule.Enabled) { 'True' } else { 'False' }
                }
                if ($rule.LocalPort) { $params.LocalPort = $rule.LocalPort }
                New-NetFirewallRule @params -ErrorAction SilentlyContinue
                Write-EventLog -Message "Created Windows Firewall rule: $ruleName" -Source $eventSource -EventLogName $eventLogName -EntryType Information
            } 
        }
    }
}

# Function to simplify the creation of an event log entry.
Function Write-EventLog {
    param(
        [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] $Message,
        [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] [string] $Source,
        [Parameter(Mandatory = $true)] [string] [ValidateNotNullOrEmpty()] [string] $EventLogName,
        [Parameter(Mandatory = $false)] [System.Diagnostics.EventLogEntryType] [ValidateNotNullOrEmpty()] $EntryType = [System.Diagnostics.EventLogEntryType]::Information
    )
    
    # Set event source and log name
    $EventSource = "CustomScriptEvent"
    $EventLogName = "Application"

    # Check whether the event source exists, and create it if it doesn't exist.
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) { [System.Diagnostics.EventLog]::CreateEventSource($EventSource, $EventLogName) }

    $log = New-Object System.Diagnostics.EventLog($EventLogName)
    $log.Source = $Source
    $log.WriteEntry($Message, $EntryType)

    # Set log directory and file
    $logDirectory = "C:\\Temp\\CseLogs"
    $logFile = Join-Path $logDirectory "$(Get-Date -Format 'yyyyMMdd').log"

    # Create the log directory if it does not exist
    if (-not (Test-Path $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory | Out-Null
    }

    # Prepare log entry
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"

    try {
        # Write log entry to the file
        Add-Content -Path $logFile -Value $logEntry
        Write-Host $logEntry
        Write-Output $logEntry
    }
    catch {
        Write-Host "Failed to write log entry to file: $($_.Exception.Message)"
        Write-Error "Failed to write log entry to file: $($_.Exception.Message)"
        thorw $_.Exception
    }
}

############################################################################################################
# Execution Body
############################################################################################################

try {
        Write-EventLog -Message "Starting installation of roles and features (timestamp: $((Get-Date).ToUniversalTime().ToString("o")))." `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Information

        Set-DefaultVmEnvironment -TempFolderPath $tempPath -TimeZone $timeZone
        Install-PowerShellWithAzModules -Url $powershellUrl -Msi $msiPath
    
    # Install required Windows Features for Domain Controller Setup
    if ($VmRole -match '^(?=.*(?:domain|dc|ad|dns|domain-controller|ad-domain|domaincontroller|ad-domain-server|ad-dns|dc-dns))(?!.*(?:cluster|cluster-node|failover-node|failover|node)).*$') {

        Set-RequiredFirewallRules -IsActiveDirectory $true 
        
        if (-not (Test-WindowsFeatureInstalled -FeatureName "AD-Domain-Services")) {
            Install-RequiredWindowsFeatures -FeatureList @("AD-Domain-Services", "RSAT-AD-PowerShell", "DNS", "NFS-Client")
        
            Set-ADDomainServices -DomainName $DomainName `
                -DomainNetBiosName $DomainNetbiosName `
                -Credential $credential
        }
        else {
            Set-ADDomainServices -DomainName $DomainName `
                -DomainNetBiosName $DomainNetbiosName `
                -Credential $credential
        }
    }
    else {
        # Install required Windows Features for Failover Cluster and File Server Setup
        Set-RequiredFirewallRules -IsActiveDirectory $false
        Install-RequiredWindowsFeatures -FeatureList @("Failover-Clustering", "RSAT-AD-PowerShell", "FileServices", "FS-FileServer", "FS-iSCSITarget-Server", "FS-NFS-Service", "NFS-Client", "TFTP-Client", "Telnet-Client")
        
        Get-WebResourcesWithRetries -SourceUrl $postConfigScriptUrl -DestinationPath "C:\\Users\\$adminName\\Desktop\\set-mscs-failover-cluster.ps1" -MaxRetries 5 -RetryIntervalSeconds 1
        Get-WebResourcesWithRetries -SourceUrl $scriptUrl -DestinationPath $scriptPath -MaxRetries 5 -RetryIntervalSeconds 1
        Write-EventLog -Message "Starting scheduled task to join the cluster to the domain (timestamp: $((Get-Date).ToUniversalTime().ToString("o")))." `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Information

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -Command `"& '$scriptPath' -DomainName '$domainName' -DomainServerIpAddress '$domainServerIpAddress' -AdminName '$AdminName' -AdminPass '$Secret'`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $trigger.EndBoundary = (Get-Date).ToUniversalTime().AddMinutes(120).ToString("o")
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Compatibility Win8 -MultipleInstances IgnoreNew
        
        Register-ScheduledTask -TaskName "Join-MscsDomain" -Action $action -Trigger $trigger -Settings $settings -User $AdminName -RunLevel Highest -Force
        Write-EventLog -Message "Scheduled task to join the cluster to the domain created (timestamp: $((Get-Date).ToUniversalTime().ToString("o")))." `
            -Source $eventSource `
            -EventLogName $eventLogName `
            -EntryType Information
    }
}
catch {
    Write-EventLog -Message $_.Exception.Message -Source $eventSource -EventLogName $eventLogName -EntryType Error 
}

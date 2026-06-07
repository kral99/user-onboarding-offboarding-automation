param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$DomainName = "company.com",
    [string]$DefaultOU = "OU=Users,DC=company,DC=local",
    [string]$InitialPassword = "ChangeMe@12345",
    [string]$ADConnectServer = "ADCONNECT01",
    [string]$UsageLocation = "US",
    [int]$SyncWaitMinutes = 30
)

# Make important errors easier to catch and handle
$ErrorActionPreference = "Stop"

# ActiveDirectory is used to create on-prem AD users and manage AD groups
Import-Module ActiveDirectory

# Microsoft Graph is used to find Entra ID users and manage Entra groups
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups

# Sign in to Microsoft Graph with the required permissions
Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All" -NoWelcome

function Split-GroupList {
    param([string]$GroupsText)

    # Return an empty array if the CSV group field is empty
    if ([string]::IsNullOrWhiteSpace($GroupsText)) {
        return @()
    }

    # Split group names by semicolon, for example: "IT Support;VPN Users"
    return $GroupsText -split ";" | ForEach-Object {
        $_.Trim()
    } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
}

function Escape-ODataString {
    param([string]$Value)

    return $Value -replace "'", "''"
}

function Start-RemoteADConnectSync {
    param([string]$ServerName)

    try {
        # Connect to the AD Connect server remotely and start a Delta Sync
        Invoke-Command -ComputerName $ServerName -ScriptBlock {
            Import-Module ADSync
            Start-ADSyncSyncCycle -PolicyType Delta
        }

        Write-Host "AD Connect Delta Sync triggered on $ServerName"
    }
    catch {
        Write-Warning "Failed to trigger AD Connect sync on $ServerName. $($_.Exception.Message)"
    }
}

function Add-UserToADGroups {
    param(
        [string]$Username,
        [string]$GroupsText
    )

    foreach ($groupName in (Split-GroupList $GroupsText)) {
        # Check if the AD group exists before adding the user
        $matchedGroups = @(Get-ADGroup -Filter { Name -eq $groupName } -ErrorAction SilentlyContinue)

        if ($matchedGroups.Count -eq 0) {
            Write-Warning "AD group not found: $groupName"
            continue
        }

        if ($matchedGroups.Count -gt 1) {
            Write-Warning "Multiple AD groups found: $groupName. Use a unique group name or DN."
            continue
        }

        try {
            Add-ADGroupMember `
                -Identity $matchedGroups[0].DistinguishedName `
                -Members $Username `
                -ErrorAction Stop

            Write-Host "Added AD group: $Username -> $groupName"
        }
        catch {
            Write-Warning "Failed to add AD group: $Username -> $groupName. $($_.Exception.Message)"
        }
    }
}

function Wait-EntraUser {
    param(
        [string]$UserPrincipalName,
        [int]$WaitMinutes
    )

    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    $safeUpn = Escape-ODataString $UserPrincipalName

    # Wait until the user appears in Entra ID after AD Connect sync
    while ((Get-Date) -lt $deadline) {
        $result = @(Get-MgUser -Filter "userPrincipalName eq '$safeUpn'" -Top 1 -ErrorAction SilentlyContinue)

        if ($result.Count -gt 0) {
            return $result[0]
        }

        Write-Host "Waiting for Entra ID user: $UserPrincipalName"
        Start-Sleep -Seconds 60
    }

    return $null
}

function Add-UserToEntraGroups {
    param(
        [string]$CloudUserId,
        [string]$UserPrincipalName,
        [string]$GroupsText
    )

    foreach ($groupName in (Split-GroupList $GroupsText)) {
        $safeGroupName = Escape-ODataString $groupName

        # Find the Entra group by display name
        $matchedGroups = @(Get-MgGroup -Filter "displayName eq '$safeGroupName'" -ErrorAction SilentlyContinue)

        if ($matchedGroups.Count -eq 0) {
            Write-Warning "Entra group not found: $groupName"
            continue
        }

        if ($matchedGroups.Count -gt 1) {
            Write-Warning "Multiple Entra groups found: $groupName. Use Group ID instead."
            continue
        }

        try {
            $body = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$CloudUserId"
            }

            New-MgGroupMemberByRef `
                -GroupId $matchedGroups[0].Id `
                -BodyParameter $body `
                -ErrorAction Stop

            Write-Host "Added Entra group: $UserPrincipalName -> $groupName"
        }
        catch {
            Write-Warning "Failed to add Entra group: $UserPrincipalName -> $groupName. $($_.Exception.Message)"
        }
    }
}

$users = @(Import-Csv $CsvPath)
$securePassword = ConvertTo-SecureString $InitialPassword -AsPlainText -Force

foreach ($user in $users) {
    $displayName = "$($user.FirstName) $($user.LastName)"
    $upn = "$($user.Username)@$DomainName"

    Write-Host "Processing AD user: $displayName"

    $existingADUser = Get-ADUser -Identity $user.Username -ErrorAction SilentlyContinue

    if (-not $existingADUser) {
        # Create the on-prem AD user
        # AD Connect will sync it
        New-ADUser `
            -Name $displayName `
            -GivenName $user.FirstName `
            -Surname $user.LastName `
            -SamAccountName $user.Username `
            -UserPrincipalName $upn `
            -DisplayName $displayName `
            -Department $user.Department `
            -Title $user.JobTitle `
            -Path $DefaultOU `
            -AccountPassword $securePassword `
            -Enabled $true `
            -ChangePasswordAtLogon $true

        Write-Host "Created AD user: $displayName"
    }
    else {
        Write-Warning "AD user already exists: $($user.Username)"
    }

    Add-UserToADGroups -Username $user.Username -GroupsText $user.ADGroups
}

# Trigger AD Connect sync only once after all AD users have been created
Start-RemoteADConnectSync -ServerName $ADConnectServer

foreach ($user in $users) {
    $upn = "$($user.Username)@$DomainName"

    # Wait for the synced user to appear in Entra ID
    $cloudUser = Wait-EntraUser -UserPrincipalName $upn -WaitMinutes $SyncWaitMinutes

    if (-not $cloudUser) {
        Write-Warning "Cloud user not found after sync wait: $upn"
        continue
    }

    Write-Host "Found Entra ID user: $upn"

    # Set UsageLocation 
    Update-MgUser -UserId $cloudUser.Id -UsageLocation $UsageLocation

    Add-UserToEntraGroups `
        -CloudUserId $cloudUser.Id `
        -UserPrincipalName $upn `
        -GroupsText $user.EntraGroups
}

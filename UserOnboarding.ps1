    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$DomainName = "company.com",
    [string]$DefaultOU = "OU=Users,DC=company,DC=local",
    [string]$InitialPassword = "ChangeMe@12345",
    [string]$ADConnectServer = "ADCONNECT01",
    [string]$UsageLocation = "US",
    [int]$SyncWaitMinutes = 30
)

# Make important errors easier to catch and handle.
$ErrorActionPreference = "Stop"

# Load the Active Directory module.
# This module provides commands like New-ADUser, Get-ADUser, Get-ADGroup, and Add-ADGroupMember.
Import-Module ActiveDirectory

# Load Microsoft Graph modules.
# These modules are used to connect to Entra ID and manage cloud users/groups.
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups

# Connect to Microsoft Graph.
# User.ReadWrite.All allows updating users, such as UsageLocation.
# Group.ReadWrite.All allows adding users to Entra ID groups.
# Directory.ReadWrite.All helps with directory-level write operations.
Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Directory.ReadWrite.All" -NoWelcome

function Split-GroupList {
    param([string]$GroupsText)

    # If the CSV group field is empty, return an empty list.
    # This prevents errors when a user has no ADGroups or EntraGroups.
    if ([string]::IsNullOrWhiteSpace($GroupsText)) {
        return @()
    }

    # This ForEach-Object runs once for each group name after splitting by semicolon.
    # Example: "IT Support;VPN Users" becomes "IT Support" and "VPN Users".
    # $_ means the current item in the pipeline.
    return $GroupsText -split ";" | ForEach-Object {
        $_.Trim()
    } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
}

function Escape-ODataString {
    param([string]$Value)

    # Microsoft Graph uses OData filters.
    # In OData, a single quote inside a string must be escaped as two single quotes.
    return $Value -replace "'", "''"
}

function Start-RemoteADConnectSync {
    param([string]$ServerName)

    try {
        # Invoke-Command runs PowerShell on a remote server.
        # We use it because Start-ADSyncSyncCycle normally works only on the AD Connect server.
        Invoke-Command -ComputerName $ServerName -ScriptBlock {
            # Load the ADSync module on the AD Connect server.
            Import-Module ADSync

            # Start a Delta Sync instead of Initial Sync.
            # Delta Sync only syncs recent changes, so it is faster for normal onboarding.
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

    # This foreach loops through each AD group listed for one user.
    # Example: if ADGroups = "IT Support;VPN Users",
    # the loop runs once for "IT Support" and once for "VPN Users".
    foreach ($groupName in (Split-GroupList $GroupsText)) {
        # Search for the AD group before adding the user.
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
            # Add this user to the current AD group from the loop.
            # DistinguishedName is used because it uniquely identifies the group.
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

    # AD Connect sync is not instant.
    # This loop checks Entra ID once per minute until the user appears or timeout is reached.
    while ((Get-Date) -lt $deadline) {
        # Get-MgUser searches for the synced Entra ID user by UPN.
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

    # This foreach loops through each Entra ID group listed for one user.
    # Example: if EntraGroups = "M365 Standard;CRM Users",
    # the loop runs once for "M365 Standard" and once for "CRM Users".
    foreach ($groupName in (Split-GroupList $GroupsText)) {
        $safeGroupName = Escape-ODataString $groupName

        # Search for the Entra group by display name.
        # In production, using Group ID is safer because display names may not be unique.
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
            # Microsoft Graph adds group members by sending an @odata.id reference.
            # This value points to the directory object ID of the user.
            $body = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$CloudUserId"
            }

            # Add the synced Entra user to the current Entra group from the loop.
            # This should be used for cloud-only groups.
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

# Import users from the CSV file.
# Each CSV row becomes one user object.
$users = @(Import-Csv $CsvPath)

# Convert the plain text password into SecureString.
# New-ADUser requires AccountPassword to be a SecureString.
$securePassword = ConvertTo-SecureString $InitialPassword -AsPlainText -Force

# This main foreach loops through every user from the CSV file.
# Each CSV row becomes one $user object.
# This first loop handles on-prem AD tasks:
# create AD user, then add AD groups.
foreach ($user in $users) {
    $displayName = "$($user.FirstName) $($user.LastName)"
    $upn = "$($user.Username)@$DomainName"

    Write-Host "Processing AD user: $displayName"

    # Check if the AD user already exists.
    # This prevents duplicate account creation.
    $existingADUser = Get-ADUser -Identity $user.Username -ErrorAction SilentlyContinue

    if (-not $existingADUser) {
        # Create the on-prem AD user.
        # In an AD Connect environment, the cloud user should be created by sync.
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

    # Add the user to on-prem AD groups from the ADGroups CSV column.
    Add-UserToADGroups -Username $user.Username -GroupsText $user.ADGroups
}

# Trigger AD Connect sync after all AD users are created.
# This is better than syncing after every single user.
Start-RemoteADConnectSync -ServerName $ADConnectServer

# This second main foreach also loops through every user from the CSV file.
# It runs after AD Connect sync is triggered.
# This loop handles cloud tasks:
# wait for the synced Entra ID user, set UsageLocation, then add Entra groups.
foreach ($user in $users) {
    $upn = "$($user.Username)@$DomainName"

    # Wait until this specific user appears in Entra ID.
    $cloudUser = Wait-EntraUser -UserPrincipalName $upn -WaitMinutes $SyncWaitMinutes

    if (-not $cloudUser) {
        Write-Warning "Cloud user not found after sync wait: $upn"
        continue
    }

    Write-Host "Found Entra ID user: $upn"

    # Set UsageLocation.
    # Many Microsoft 365 license assignments require UsageLocation before license can apply.
    Update-MgUser -UserId $cloudUser.Id -UsageLocation $UsageLocation

    # Add this synced cloud user to the EntraGroups listed in the CSV.
    Add-UserToEntraGroups `
        -CloudUserId $cloudUser.Id `
        -UserPrincipalName $upn `
        -GroupsText $user.EntraGroups
}

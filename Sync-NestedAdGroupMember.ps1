<#
    .SYNOPSIS
    Fetches members of AD groups with name suffix -NESTED recursively and syncs them to their -UNNESTED counterpart.

    .DESCRIPTION
    The Sync-NestedAdGroupMember.ps1 script syncs members between pairs of groups.
    A pair consists of two groups with an identical name followed by the suffix -NESTED for one group and -UNNESTED for the other,
    where the nested group is the source of truth for the members. You can theoretically create an infinite amount of those pairs in your Active Directory.

    During execution the script fetches all AD groups with suffix -NESTED, loops thru them and looks for their -UNNESTED counterpart.
    Then all members of the -NESTED group are fetched recursively and synced to the -UNNESTED group.
    This means missing members are added and obsolete members are removed.
    Manual changes to the -UNNESTED group are overwritten.

    .LINK
    https://github.com/dominikduennebacke/Sync-NestedAdGroupMember

    .NOTES
    - Version: 0.9.0
    - License: GPL-3.0
    - Author:   Dominik Dünnebacke
        - Email:    dominik@duennebacke.com
        - GitHub:   https://github.com/dominikduennebacke
        - LinkedIn: https://www.linkedin.com/in/dominikduennebacke/

    .INPUTS
    Hashtable
    A hashtable is received by the LegacyPair parameter.

    .OUTPUTS
    None or PSCustomObject
    Returns the nested group, unnested group, user and modification type as PSCustomObject if the PassThru parameter is specified. By default, this cmdlet does not generate any output.

    .EXAMPLE
    Syncs all pairs and provides output.

    .\Sync-NestedAdGroupMember.ps1 -VERBOSE

    VERBOSE: Checking dependencies
    VERBOSE: The secure channel between the local computer and the domain is in good condition.
    VERBOSE: Fetching NESTED AD groups
    VERBOSE: Syncing group members recursively from NESTED group(s) to UNNESTED group(s)
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) john.doe
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) sam.smith
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (-) tom.tonkins
    
    .EXAMPLE
    Syncs all pairs and provides output. Two additional group pairs that are outside the naming convention are considered provided by the LegacyPair parameter.

    .\Sync-NestedAdGroupMember.ps1 -LegacyPair @{"app-dummy-access-NESTED" = "legacyapp1-access"; "app-dummy-access-NESTED" = "legacyapp2-access";} -VERBOSE

    VERBOSE: Checking dependencies
    VERBOSE: The secure channel between the local computer and the domain is in good condition.
    VERBOSE: Fetching NESTED AD groups
    VERBOSE: Syncing group members recursively from NESTED group(s) to UNNESTED group(s)
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) john.doe
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) sam.smith
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) tom.tonkins
    VERBOSE: app-dummy-access-NESTED > legacyapp1-access
    VERBOSE: app-dummy-access-NESTED > legacyapp1-access: (+) john.doe
    VERBOSE: app-dummy-access-NESTED > legacyapp1-access: (+) sam.smith
    VERBOSE: app-dummy-access-NESTED > legacyapp1-access: (+) tom.tonkins
    VERBOSE: app-dummy-access-NESTED > legacyapp2-access
    VERBOSE: app-dummy-access-NESTED > legacyapp2-access: (+) john.doe
    VERBOSE: app-dummy-access-NESTED > legacyapp2-access: (+) sam.smith
    VERBOSE: app-dummy-access-NESTED > legacyapp2-access: (+) tom.tonkins
    
    .EXAMPLE
    Provides output of sync changes but does not actually perform them.

    .\Sync-NestedAdGroupMember.ps1 -WhatIf:$true

    What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) john.doe
    What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) sam.smith
    What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (-) tom.tonkins
    
    .EXAMPLE
    Provides output of sync changes but does not actually perform them, with additional output.

    .\Sync-NestedAdGroupMember.ps1 -WhatIf:$true -VERBOSE

    VERBOSE: Checking dependencies
    VERBOSE: The secure channel between the local computer and the domain is in good condition.
    VERBOSE: Fetching NESTED AD groups
    VERBOSE: Syncing group members recursively from NESTED group(s) to UNNESTED group(s)
    VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED
    What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) john.doe
    What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) sam.smith
    What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (-) tom.tonkins
    
    .EXAMPLE
    Only consideres the OU "OU=groups,DC=contoso,DC=com" looking for group pairs. This can speed up execution.

    .\Sync-NestedAdGroupMember.ps1 -SearchBase "OU=groups,DC=contoso,DC=com"
#>


# -------------------------------------------------------------------------------------------------------------- #
#region Parameters
param (
    # Specifies an Active Directory path to search under
    [string]$SearchBase,

    # Additional pairs that are outside the `-NESTED` / `-UNNESTED` naming convention
    [hashtable]$LegacyPair,

    # Specifies the Active Directory Domain Services instance to connect to
    [string]$Server,

    # Shows what would happen if the cmdlet runs
    [switch]$WhatIf,

    # Returns the nested group, unnested group, user and modification type as PSCustomObject.
    [switch]$PassThru,

    # Suffix that is used for NESTED groups
    [parameter(DontShow)]
    [string]$NestedSuffix = "-NESTED",
    
    # Suffix that is used for UNNESTED groups
    [parameter(DontShow)]
    [string]$UnnestedSuffix = "-UNNESTED"
)
#endregion Parameters


# -------------------------------------------------------------------------------------------------------------- #
#region Checking dependencies
Write-Verbose "Checking dependencies"

# Determine if PowerShell module ActiveDirectory is installed
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
    throw "PowerShell module 'ActiveDirectory' is not installed"
}

# Determine domain controller to use for AD cmdlets (if $Server is not set)
if (-not $Server) {
    $Server = (Get-ADDomainController -Discover).HostName
}
if (-not $Server) {
    throw "No AD domain controller was found"
}


# Test connection to server
if (-not (Test-ComputerSecureChannel -Server $Server)) {
    throw "Connection to $Server failed"
}

# Determine SearchBase if not set (as cmdlets do not allow an empty SearchBase)
if (-not $SearchBase) {
    $SearchBase = (Get-ADDomain -Server $Server).DistinguishedName
}
#endregion Checking dependencies


# -------------------------------------------------------------------------------------------------------------- #
#region Fetching NESTED AD groups
Write-Verbose "Fetching NESTED AD groups"

# Fetching NESTED AD groups by filtering for suffix "-NESTED"
$Params = @{
    SearchBase = $SearchBase
    Filter     = "Name -like '*$($NestedSuffix)'"
    Server     = $Server
}
[array]$NestedGroups = Get-ADGroup @Params

# Fetching NESTED AD groups from LegacyPair parameter
foreach ($Key in $LegacyPair.Keys) {
    if ($NestedGroups.Name -notcontains $Key) {
        $Params = @{
            SearchBase = $SearchBase
            Filter     = "Name -eq '$Key'"
            Server     = $Server
        }
        $NestedGroups += Get-ADGroup @Params
    } 
}

# Sort groups by name
$NestedGroups = $NestedGroups | Sort-Object Name
#endregion Fetching NESTED AD groups


# -------------------------------------------------------------------------------------------------------------- #
#region Syncing group members recursively from NESTED group(s) to UNNESTED group(s)
Write-Verbose "Syncing group members recursively from NESTED group(s) to UNNESTED group(s)"

foreach ($Group in $NestedGroups) {

    # Building UNNESTED AD group name
    $UnnestedGroupName = $Group.Name -replace $NestedSuffix, $UnnestedSuffix

    # Finding associated UNNESTED AD group by Get-ADGroup filter query
    [array]$UnnestedGroups = Get-ADGroup -Filter "name -eq '$UnnestedGroupName'" -Server $Server

    # Finding associated UNNESTED AD group by LegacyPair parameter
    $UnnestedGroups += foreach ($Value in $LegacyPair.$($Group.Name)) {
        if ($UnnestedGroups.Name -notcontains $Value) {
            Get-ADGroup -Identity $Value -Server $Server
        }
    }

    # Sort groups by name
    $UnnestedGroups = $UnnestedGroups | Sort-Object Name

    # Jump to next item in NESTED groups array if no UNNESTED group was found
    if (-not $UnnestedGroups) {
        Write-Warning "No associated unnested AD group(s) found for $($Group.Name)"
        Continue
    }

    # Fetch members of NESTED group
    $MembersNested = Get-ADGroupMember -Identity $Group -Recursive -Server $Server | Sort-Object SamAccountName

    # Loop thru UNNESTED group(s)
    foreach ($UnnestedGroup in $UnnestedGroups) {

        # Output for reference
        Write-Verbose "$($Group.Name) > $($UnnestedGroup.Name)"

        # Fetch members of UNNESTED group
        $MembersUnnested = Get-ADGroupMember -Identity $UnnestedGroup.Name -Server $Server | Sort-Object SamAccountName

        # Determine missing and obsolete members of UNNESTED group
        $MissingMembers = $MembersNested | Where-Object { $MembersUnnested.SID -notcontains $_.SID }
        $ObsoleteMembers = $MembersUnnested | Where-Object { $MembersNested.SID -notcontains $_.SID }

        # Handle WhatIf
        if ($WhatIf) {

            # Add missing members to UNNESTED group (WhatIf)
            foreach ($Member in $MissingMembers) {
                Write-Host "What if: $($Group.Name) > $($UnnestedGroup.Name): (+) $($Member.SamAccountName)"
            }

            # Remove missing members from UNNESTED group (WhatIf)
            foreach ($Member in $ObsoleteMembers) {
                Write-Host "What if: $($Group.Name) > $($UnnestedGroup.Name): (-) $($Member.SamAccountName)"
            }    
        }
        else {

            # Add missing members to UNNESTED group
            foreach ($Member in $MissingMembers) {
                Write-Verbose "$($Group.Name) > $($UnnestedGroup.Name): (+) $($Member.SamAccountName)"
                Add-ADGroupMember -Identity $UnnestedGroup.Name -Members $Member -Confirm:$false -Server $Server

                # Provide output in case $PassThru is set
                if ($PassThru) {
                    [PSCustomObject]@{
                        NestedGroup   = $Group.Name
                        UnnestedGroup = $UnnestedGroup.Name
                        User          = $Member.SamAccountName
                        Action        = "Add"
                    }
                }
            }

            # Remove missing members from UNNESTED group
            foreach ($Member in $ObsoleteMembers) {
                Write-Verbose "$($Group.Name) > $($UnnestedGroup.Name): (-) $($Member.SamAccountName)"
                Remove-ADGroupMember -Identity $UnnestedGroup.Name -Members $Member -Confirm:$false -Server $Server
                
                # Provide output in case $PassThru is set
                if ($PassThru) {
                    [PSCustomObject]@{
                        NestedGroup   = $Group.Name
                        UnnestedGroup = $UnnestedGroup.Name
                        User          = $Member.SamAccountName
                        Action        = "Remove"
                    }
                }
            }
        }
    }
}
#endregion Syncing group members recursively from NESTED group(s) to UNNESTED group(s)
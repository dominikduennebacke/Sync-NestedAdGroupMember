# Sync-NestedAdGroupMember

## Synopsis
Fetches members of AD groups with name suffix `-NESTED` recursively and syncs them to their `-UNNESTED` counterpart.

## Syntax
```powershell
.\Sync-NestedAdGroupMember.ps1 [-SearchBase <String>] [-LegacyPair <Hashtable>] [-Server <String>] [-WhatIf] [-PassThru] [-VERBOSE]
```

## Description
The Sync-NestedAdGroupMember.ps1 script syncs members between pairs of groups. A pair consists of two groups with an identical name followed by the suffix `-NESTED` for one group and `-UNNESTED` for the other, where the nested group is the source of truth for the members. You can theoretically create an infinite amount of those pairs in your Active Directory.

During execution the script fetches all AD groups with suffix `-NESTED`, loops thru them and looks for their `-UNNESTED` counterpart. Then all members of the `-NESTED` group are fetched recursively and synced to the `-UNNESTED` group. This means missing members are added and obsolete members are removed. Manual changes to the `-UNNESTED` group are overwritten.

### Use case
There are many applications that do not support nested group membership of users breaking with common access management models. This script serves as a workaround. The idea is that the `-UNNESTED` group is configured within the application and access is managed entirely in the `-NESTED` group.

### Requirements
* PowerShell module [ActiveDirectory](https://learn.microsoft.com/en-us/powershell/module/activedirectory/?view=windowsserver2022-ps)
* Execution on a domain-joined Windows machine that has an active connection to a domain controller
* Execution by a user with permission to add/remove members in target AD groups

### Installation
* Download the script file:
    ```powershell
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dominikduennebacke/Sync-NestedAdGroupMember/main/Sync-NestedAdGroupMember.ps1" -OutFile "Sync-NestedAdGroupMember.ps1"
    ```
* Set up a scheduled task or a CI/CD job that runs the script every 5-10 minutes

### Scaling
After setting up a few group pairs keep an eye on the execution time of the script which should not be larger than the scheduling interval.

## Examples

### Example 1
Syncs all pairs and provides output.
```powershell
.\Sync-NestedAdGroupMember.ps1 -VERBOSE
```
```
VERBOSE: Checking dependencies
VERBOSE: The secure channel between the local computer and the domain is in good condition.
VERBOSE: Fetching NESTED AD groups
VERBOSE: Syncing group members recursively from NESTED group(s) to UNNESTED group(s)
VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED
VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) john.doe
VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) sam.smith
VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (-) tom.tonkins
```

### Example 2
Syncs all pairs and provides output. Two additional group pairs that are outside the naming convention are considered provided by the `LegacyPair` parameter.
```powershell
.\Sync-NestedAdGroupMember.ps1 -LegacyPair @{"app-dummy-access-NESTED" = "legacyapp1-access"; "app-dummy-access-NESTED" = "legacyapp2-access";} -VERBOSE
```
```
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
```

### Example 3
Provides output of sync changes but does not actually perform them.
```powershell
.\Sync-NestedAdGroupMember.ps1 -WhatIf:$true
```
```
What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) john.doe
What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) sam.smith
What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (-) tom.tonkins
```

### Example 4
Provides output of sync changes but does not actually perform them, with additional output.
```powershell
.\Sync-NestedAdGroupMember.ps1 -WhatIf:$true -VERBOSE
```
```
VERBOSE: Checking dependencies
VERBOSE: The secure channel between the local computer and the domain is in good condition.
VERBOSE: Fetching NESTED AD groups
VERBOSE: Syncing group members recursively from NESTED group(s) to UNNESTED group(s)
VERBOSE: app-dummy-access-NESTED > app-dummy-access-UNNESTED
What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) john.doe
What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (+) sam.smith
What if: app-dummy-access-NESTED > app-dummy-access-UNNESTED: (-) tom.tonkins
```

### Example 5
Only consideres the OU `"OU=groups,DC=contoso,DC=com"` looking for group pairs. This can speed up execution.
```powershell
.\Sync-NestedAdGroupMember.ps1 -SearchBase "OU=groups,DC=contoso,DC=com"
```

## Parameters

### -SearchBase
Specifies an Active Directory path to search under.

```yaml
Type: String
Parameter Sets: (All)
Aliases: 

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -LegacyPair
Sometimes it can be tedious to replace an access group within an application because of other dependencies or politics. For that additional pairs that are outside the `-NESTED` / `-UNNESTED` naming convention can be provided as a hashtable.

```yaml
Type: Hashtable
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Server
Specifies the Active Directory Domain Services instance to connect to.

```yaml
Type: String
Parameter Sets: (All)
Aliases: 

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -PassThru
Returns the name of the nested group, name of the unnested group, SamAccountName of the user and modification type (Add or Remove) as PSCustomObject.
If -PassThru is not specified, this cmdlet does not generate any output.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: 

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -VERBOSE
Provides additional output about the process.

## INPUTS

### Hashtable
A hashtable is received by the LegacyPair parameter.

## OUTPUTS

### None or PSCustomObject
Returns the name of the nested group, name of the unnested group, SamAccountName of the user and modification type (Add or Remove) as PSCustomObject if the PassThru parameter is specified.
By default, this cmdlet does not generate any output.
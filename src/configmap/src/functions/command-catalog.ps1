function Get-ScriptParameterInfo {
    <#
    .SYNOPSIS
        Extracts parameter metadata (name, type, switch, ValidateSet, default) from a scriptblock.
    #>
    [OutputType([pscustomobject])]
    param(
        [scriptblock]$Func,
        [int]$Skip = 0,
        $Exclude = @('$_context', '$_self'),
        [System.Collections.IDictionary]$Entry = $null
    )

    if (!$Func -or !$Func.AST.ParamBlock -or !$Func.AST.ParamBlock.Parameters) {
        return @()
    }

    $scriptArgs = Get-ScriptArgs -func $Func -skip $Skip -exclude $Exclude -entry $Entry
    $defaultsByName = @{}
    $skipped = 0

    foreach ($paramAst in $Func.AST.ParamBlock.Parameters) {
        $nameWithDollar = "$($paramAst.Name)"
        if ($nameWithDollar -in $Exclude) {
            continue
        }
        if ($skipped -lt $Skip) {
            $skipped++
            continue
        }

        $paramName = $paramAst.Name.ToString().Trim('$')
        $defaultValue = $null
        if ($null -ne $paramAst.DefaultValue) {
            try {
                $defaultValue = $paramAst.DefaultValue.SafeGetValue()
            }
            catch {
                $defaultValue = $paramAst.DefaultValue.Extent.Text
            }
        }
        $defaultsByName[$paramName] = $defaultValue
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $scriptArgs.Keys) {
        $dynParam = $scriptArgs[$name]
        $validateSet = @()
        foreach ($attr in $dynParam.Attributes) {
            if ($attr -is [System.Management.Automation.ValidateSetAttribute]) {
                $validateSet = @($attr.ValidValues)
                break
            }
        }

        $isSwitch = $dynParam.ParameterType -eq [switch]
        $typeName = if ($dynParam.ParameterType -eq [string]) { 'string' }
        elseif ($dynParam.ParameterType -eq [int] -or $dynParam.ParameterType -eq [int32]) { 'int' }
        elseif ($dynParam.ParameterType -eq [bool]) { 'bool' }
        elseif ($isSwitch) { 'switch' }
        elseif ($dynParam.ParameterType.Namespace -eq 'System') { $dynParam.ParameterType.Name }
        else { $dynParam.ParameterType.FullName }

        $result.Add([pscustomobject]@{
                Name         = $name
                Type         = $typeName
                IsSwitch     = $isSwitch
                ValidateSet  = $validateSet
                DefaultValue = $(if ($defaultsByName.ContainsKey($name)) { $defaultsByName[$name] } else { $null })
            }) | Out-Null
    }

    return @($result)
}

function Get-ConfigMapCommandCatalog {
    <#
    .SYNOPSIS
        Returns a structured catalog of map commands and their parameters for agents and automation.
    .PARAMETER Map
        An imported config map (hashtable/ordered dictionary).
    .PARAMETER Path
        Optional entry name to describe a single command. Throws if not found.
    .PARAMETER Language
        Map language: build or conf.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ $_ -is [System.Collections.IDictionary] })]
        $Map,
        [string]$Path,
        [ValidateSet('build', 'conf')]$Language = 'build'
    )

    $scripts = Get-CompletionList $Map -language $Language
    $reservedKeys = (Get-MapLanguage $Language).reservedKeys

    $scriptItems = if ($Map -is [System.Collections.Specialized.OrderedDictionary]) {
        @($scripts.GetEnumerator())
    }
    else {
        @($scripts.GetEnumerator() | Sort-Object Name)
    }

    if ($PSBoundParameters.ContainsKey('Path') -and $null -ne $Path -and $Path -ne '') {
        $match = $scriptItems | Where-Object { $_.Name -eq $Path }
        if (-not $match) {
            # Case-insensitive fallback
            $match = $scriptItems | Where-Object { $_.Name -ieq $Path }
        }
        if (-not $match) {
            throw "Entry '$Path' not found. Run 'qbuild !describe' to see all available commands."
        }
        $scriptItems = @($match)
    }

    foreach ($item in $scriptItems) {
        $name = $item.Name
        $script = $item.Value

        if ($name -in $reservedKeys) {
            continue
        }

        $isParent = Test-IsParentEntry $script -Language $Language -ReservedKeys $reservedKeys

        $description = ''
        if ($script -is [System.Collections.IDictionary] -and $script.description) {
            $description = [string]$script.description
        }

        $parameters = @()
        try {
            $entryCommand = Get-EntryCommand $script 'exec'
        }
        catch {
            $entryCommand = $null
        }

        if ($entryCommand -is [scriptblock]) {
            $entryContext = if ($script -is [System.Collections.IDictionary]) { $script } else { $null }
            $parameters = @(Get-ScriptParameterInfo -Func $entryCommand -Entry $entryContext)
        }

        [pscustomobject]@{
            Name        = $name
            Description = $description
            IsParent    = [bool]$isParent
            Parameters  = $parameters
        }
    }
}

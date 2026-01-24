function Get-EntryDynamicParam(
    [System.Collections.IDictionary] $map,
    $key,
    $command,
    [int]$skip = 0,
    $bound
) {
    if (!$key) { return @() }

    $selectedEntry = Get-MapEntry $map $key
    if (!$selectedEntry) { return @() }

    # Use the command parameter to determine which command to extract, defaulting to "exec"
    $commandKey = $command ? $command : "exec"
    $entryCommand = Get-EntryCommand $selectedEntry $commandKey
    if (!$entryCommand) { return @() }
    $p = Get-ScriptArgs $entryCommand -skip $skip

    return $p
}

function Get-ScriptArgs {
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param(
        [scriptblock]$func,
        [int]$skip = 0
    )
    function Get-SingleArg {
        [OutputType([System.Management.Automation.RuntimeDefinedParameter])]
        param([System.Management.Automation.Language.ParameterAst] $ast)

        $paramAttributesCollect = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]

        $paramAttribute = New-Object -Type System.Management.Automation.ParameterAttribute
        $paramAttributesCollect.Add($paramAttribute)

        $paramType = $ast.StaticType

        foreach ($attr in $ast.Attributes) {
            if ($attr -is [System.Management.Automation.Language.TypeConstraintAst]) {
                if ($attr.TypeName.ToString() -eq "switch") {
                    $paramType = [switch]
                }
                else {
                    # $newAttr = New-Object -type System.Management.Automation.PSTypeNameAttribute($attr.TypeName.Name)
                    # $paramAttributesCollect.Add($newAttr)
                }
            }
        }

        # Create parameter with name, type, and attributes
        $name = $ast.Name.ToString().Trim("`$")
        $dynParam = New-Object -Type System.Management.Automation.RuntimeDefinedParameter($name, $paramType, $paramAttributesCollect)

        return $dynParam
    }

    $exclude = @("`$_context", "`$_self")

    # Add parameter to parameter dictionary and return the object
    $paramDictionary = New-Object `
        -Type System.Management.Automation.RuntimeDefinedParameterDictionary

    # Check if ParamBlock exists before accessing Parameters
    if ($func.AST.ParamBlock -and $func.AST.ParamBlock.Parameters) {
        $parameters = $func.AST.ParamBlock.Parameters

        $skipped = 0
        foreach ($param in $parameters) {
            if ("$($param.Name)" -in $exclude) {
                continue
            }
            if ($skipped -lt $skip) {
                $skipped++
                continue
            }
            $dynParam = Get-SingleArg $param
            $paramDictionary.Add($dynParam.Name, $dynParam)
        }
    }

    return $paramDictionary
}

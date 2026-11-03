$targets = @{
    "build" = {
        param($ctx, [bool][switch]$noRestore)

        $bound = $PSBoundParameters
        write-host "build script body"
        write-host "ctx=$($ctx | convertto-json)"
        write-host "noRestore=$noRestore"
        write-host "bound=$($bound | ConvertTo-Json)"
    }
}

function get-single-arg {
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

function get-script-args($func) {
    # todo: convert AST parameters to DynamicParam
    $parameters = $func.AST.ParamBlock.Parameters

    # Add parameter to parameter dictionary and return the object
    $paramDictionary = New-Object `
        -Type System.Management.Automation.RuntimeDefinedParameterDictionary
    
    foreach ($param in $parameters) {
        $dynParam = get-single-arg $param
        $paramDictionary.Add($dynParam.Name, $dynParam)
    }
    return $paramDictionary
}
function invoke-build {
    [CmdletBinding()]
    param ($target)

    DynamicParam {
        $p = get-script-args $targets.$target

        return $p
    }
    begin {}
    process {
        $p = $PSBoundParameters
        write-host "build $p"
    }
}

return $targets
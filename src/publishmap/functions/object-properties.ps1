
function get-propertynames($obj) {
    
    if ($obj -is [System.Collections.IDictionary]) {
        return $obj.keys
    }
    return $obj.psobject.Properties | select -ExpandProperty name
}

function add-properties([Parameter(Mandatory=$true, ValueFromPipeline = $true)] $object, $props, [switch][bool] $ifNotExists, $exclude = @()) {
    foreach($prop in get-propertynames $props) {
        if ($prop -notin $exclude) {
            add-property $object -name $prop -value $props.$prop -ifnotexists:$ifnotexists
        }
    }
}

function add-property {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $object, 
        [Parameter(Mandatory=$true)] $name, 
        [Parameter(Mandatory=$true)] $value, 
        [switch][bool] $ifNotExists
    ) 

    if ($object.$name -ne $null) {
        if ($ifNotExists) { return }
        throw "property '$name' already exists with value '$value'"
    }
    if ($object -is [System.Collections.IDictionary]) {
        $object.add($name, $value)
    }
    else {
        $object | add-member -name $name -membertype noteproperty -value $value
    }
}


function ConvertTo-Object([hashtable]$hashtable) {
    $copy = @{}
    $copy += $hashtable
    foreach($key in $hashtable.Keys) {
        $val = $hashtable[$key]
        if ($val -is [hashtable]) {
            $obj = ConvertTo-Object $val
            $copy[$key] = $obj
        }

    }
    return New-Object -TypeName PSCustomObject -Property $copy 
}

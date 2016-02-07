
function get-propertynames($obj) {
    
    if ($obj -is [System.Collections.IDictionary]) {
        return $obj.keys
    }
    return $obj.psobject.Properties | select -ExpandProperty name
}

function add-properties(
    [Parameter(Mandatory=$true, ValueFromPipeline = $true)] 
    $object,
     [Parameter(Mandatory=$true)]
     $props, 
     [switch][bool] $ifNotExists, 
     [switch][bool] $merge, 
     $exclude = @()
 ) {
    foreach($prop in get-propertynames $props) {
        if ($prop -notin $exclude) {
            $r = add-property $object -name $prop -value $props.$prop -ifnotexists:$ifnotexists -merge:$merge
        }
    }
    return $object
}

function add-property {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)] $object, 
        [Parameter(Mandatory=$true)] $name, 
        [Parameter(Mandatory=$true)] $value, 
        [switch][bool] $ifNotExists,
        [switch][bool] $overwrite,
       [switch][bool] $merge
    ) 
    try {
    if ($object.$name -ne $null) {
        if ($merge -and $object.$name -is [System.Collections.IDictionary] -and $value -is [System.Collections.IDictionary]) {
            $r = add-properties $object.$name $value -ifNotExists:$ifNotExists -merge:$merge 
            return $object
        }
        elseif ($ifNotExists) { return }
        elseif ($overwrite) {
            $object.$name = $value 
        }
        else {
            throw "property '$name' already exists with value '$value'"
        }
    }
    if ($object -is [System.Collections.IDictionary]) {
        $object[$name] = $value
    }
    else {
        $object | add-member -name $name -membertype noteproperty -value $value
        #$object.$name = $value 
    }

    return $object
    } catch {
        throw
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


function copy-hashtable($hash) {
    $new = @{}
    foreach($key in get-propertynames $hash) {
        if ($hash.$key -is [System.Collections.IDictionary]) {
            $new.$key = copy-hashtable $hash.$key
        } else {
            $new.$key = $hash.$key
        }   
    }

    return $new
}
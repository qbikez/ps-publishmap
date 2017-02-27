
function get-propertynames($obj) {
    Measure-function "$($MyInvocation.MyCommand.Name)" {    
        if ($obj -is [System.Collections.IDictionary]) {
            return $obj.keys
        }
        return $obj.psobject.Properties | select -ExpandProperty name
    }
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
    Measure-function  "$($MyInvocation.MyCommand.Name)" {
        foreach($prop in get-propertynames $props) {
            if ($prop -notin $exclude) {
                try {
                    $r = add-property $object -name $prop -value $props.$prop -ifnotexists:$ifnotexists -merge:$merge
                } catch {
                    throw "failed to add property '$prop' with value '$props.$prop': $($_.Exception.Message)"
                }
            }
        }
        return $object
    }
}

function add-property {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Position=1)] $object, 
        [Parameter(Mandatory=$true,Position=2)] $name, 
        [Parameter(Mandatory=$true,Position=3)] $value, 
        [switch][bool] $ifNotExists,
        [switch][bool] $overwrite,
        [switch][bool] $merge
    ) 
   # Measure-function  "$($MyInvocation.MyCommand.Name)" {
        try {
            if ($null -ne $object.$name) {
                if ($merge -and $object.$name -is [System.Collections.IDictionary] -and $value -is [System.Collections.IDictionary]) {
                    $r = add-properties $object.$name $value -ifNotExists:$ifNotExists -merge:$merge 
                    return $object
                }
                elseif ($ifNotExists) {
                    return 
                }
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
                $null = $object | add-member -name $name -membertype noteproperty -value $value
                #$object.$name = $value 
            }

            return $object
        } catch {
            throw
        }
#    }
}

function ConvertTo-Hashtable([Parameter(ValueFromPipeline=$true)]$obj, [switch][bool]$recurse) {
    Measure-function  "$($MyInvocation.MyCommand.Name)" {

        $object =$obj
        if (!$recurse -and ($object -is [System.Collections.IDictionary] -or $object -is [array])) {
            return $object
        }
 
        if($object -is [array]) {
            if ($recurse) {
                for($i = 0; $i -lt $object.Length; $i++) {
                    $object[$i] = ConvertTo-Hashtable $object[$i] -recurse:$recurse
                }
            }
            return $object
        } 
        elseif ($object -is [System.Collections.IDictionary] -or  $object -is [System.Management.Automation.PSCustomObject] -or $true) {
            $h = @{}
            $props = get-propertynames $object
            foreach ($p in $props) {
                if ($recurse) {
                    $h[$p] = ConvertTo-Hashtable $object.$p -recurse:$recurse
                } else {
                    $h[$p] = $object.$p
                }
            }
            return $h
        } else {
            throw "could not convert object to hashtable"
            #return $object
        }
    }
	
}


function ConvertTo-Object([Parameter(ValueFromPipeline=$true)]$hashtable, $recurse) {    
    Measure-function  "$($MyInvocation.MyCommand.Name)" {
        if ($hashtable -is [hashtable]) {
            $copy = @{}
            $copy += $hashtable
            foreach($key in = get-propertynames $hashtable) {
                $val = $hashtable[$key]
                $obj = ConvertTo-Object $val -recurse $recurse
                $copy[$key] = $obj            
            }
            return New-Object -TypeName PSCustomObject -Property $copy 
        } 
        elseif ($hashtable -is [System.Management.Automation.PSCustomObject]) {
            $copy = @{}
            foreach($key in get-propertynames $hashtable) {
                $val = $hashtable.$key
                $obj = ConvertTo-Object $val -recurse $recurse
                $copy[$key] = $obj            
            }
            return New-Object -TypeName PSCustomObject -Property $copy 
        } 
        elseif ($hashtable -is [Array]) {        
            return $hashtable
        }
        else {
            return $hashtable
        }   
    }
}


function copy-hashtable($hash) {
    Measure-function  "$($MyInvocation.MyCommand.Name)" {

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
}
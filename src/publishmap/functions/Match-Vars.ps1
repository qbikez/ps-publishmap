<#
    .PARAMETER simpleMode 
    for better performance. do not perform variable substitution based on self and root
    should still work for simpler scenarios

#>

function _clone($obj, [switch][bool] $deep, [int]$level = 0, [int]$maxdepth = 10, $shallowkeys = @(), $path) {
    try {
    #        Measure-function  "$($MyInvocation.MyCommand.Name)" {
    $shkeys = $shallowkeys + @("_clone_meta")    
    if ($level -gt $maxdepth) {
        throw "max clone depth exceeded!"
    }
    if ($obj -is [System.Collections.Specialized.OrderedDictionary]) {       
        $copy = [ordered]@{}
        foreach ($e in $obj.GetEnumerator()) {
            $val = $e.Value
            if ($deep -and !($e.key -in $shkeys)) { $val = _clone $val -deep:$deep -maxdepth:$maxdepth -level ($level + 1) -shallowkeys:$shallowkeys -path "$path.$($e.key)" }
            $copy.Add($e.Key, $val)
        }
        if ($obj["_clone_meta"] -eq $null) {
            $obj["_clone_meta"] = @{ "type" = "original" }
        }
        $copy["_clone_meta"] = @{ "type" = "clone" }

        return $copy
    }
    elseif ($obj.gettype().name -eq "Hashtable" -or $obj -is [Hashtable]) {
        # hashtable created in c# code will have case-sensitive keys. convert it back to PS-style case-insensitive
       
        $copy = @{}
        
        foreach ($e in $obj.GetEnumerator()) {
            $val = $e.Value
            if ($deep -and !($e.key -in $shkeys)) { $val = _clone $val -deep:$deep -maxdepth:$maxdepth  -level ($level + 1) -shallowkeys:$shallowkeys -path "$path.$($e.key)" }
            try {
                $copy.Add($e.Key, $val)
            } catch {
                throw "failed to copy object '$path': $($_.Exception.Message)"
            }
        }
        if ($obj["_clone_meta"] -eq $null) {
            $obj["_clone_meta"] = @{ "type" = "original" }
        }
        $copy["_clone_meta"] = @{ "type" = "clone" }
        return $copy
    }
    elseif ($obj.gettype().IsArray) {
        if ($deep) {
            Write-Verbose "don't know how to deep-clone an array. doing a shallow clone."
        }
        return @($obj.Clone())        
    }    
    elseif ($obj.gettype().IsValueType) {
        return $obj
    }
    elseif ($obj -is [string]) {
        return $obj.Clone()
    }
    elseif ($obj.Clone -ne $null) {
        return $obj.Clone()
    }
    else {
        return $obj
    }
    #       }
    } catch {
        throw
    }
}

function get-entry(
    [Parameter(mandatory = $true, Position = 1)] $key,
    [Parameter(mandatory = $true, ValueFromPipeline = $true, Position = 2)] $map,
    $excludeProperties = @("project"),
    [switch][bool] $simpleMode = $false,
    [switch][bool] $noVarReplace = $false) {
    #        Measure-function  "$($MyInvocation.MyCommand.Name)" {

    $root = $map
    $parent = $null
    $entry = $null
    $key_org = $key
    $splits = $key.split(".")
    for ($i = 0; $i -lt $splits.length; $i++) {
        $split = $splits[$i]
        $parent = $entry
        if ($i -eq $splits.length - 1) {
            $key = $split
            if ($null -ne $map[$key]) { 
                $entry = $map[$key] 
                $vars = @{}
            }
            elseif ($key -eq "/" -or $key -eq "\") {
                $entry = $map
                $vars = @{}
            } 
            else {     
                foreach ($kvp in $map.GetEnumerator()) {
                    $pattern = $kvp.key
                    $vars = _MatchVarPattern $key "$pattern"
                    if ($null -ne $vars) {
                        $entry = $kvp.value   
                        break
                    }
                }
            }

            if ($null -ne $entry) {
                #TODO: should we use a deep clone?
                $entry2 = _clone $entry -deep -shallowkeys @("project") -path $key_org
                if ($entry2 -is [Hashtable] -or $entry2 -is [System.Collections.Specialized.OrderedDictionary]) {
                    $entry2["_vars"] = $vars
                }             
                $warnaction = "SilentlyContinue"
                if ($simpleMode) {
                    $warnaction = "Continue" 
                }
                if (!$noVarReplace) {
                    $allvars = $vars

                    $entry2 = Convert-PropertiesFromVars $entry2 -vars $allvars -exclude $excludeProperties -WarningAction $warnaction -path $entry2._fullpath
                    if (!$simpleMode) {
                        $entry2 = Convert-PropertiesFromVars $entry2 -vars $map -exclude $excludeProperties -WarningAction $warnaction -path $entry2._fullpath
                        $entry2 = Convert-PropertiesFromVars $entry2 -vars $root -exclude $excludeProperties -WarningAction $warnaction -path $entry2._fullpath
                    }
                    # if (!$simpleMode) {
                    #     try {
                    #         foreach ($kvp in $map.GetEnumerator()) {
                    #             # only use self vars as fallback 
                    #             if ($allvars[$kvp.key] -eq $null) {
                    #                 $allvars[$kvp.key] = $kvp.value
                    #             }
                    #         }                       
                    #         foreach ($kvp in $root.GetEnumerator()) {
                    #             # only use root vars as fallback
                    #             if ($allvars[$kvp.key] -eq $null) {
                    #                 $allvars[$kvp.key] = $kvp.value
                    #             }
                    #         }   
                    #     } catch {
                    #         throw
                    #     }                    
                    # }

                    # # replacement with $map and $root variable should be done in separate steps!
                    # $entry2 = Convert-PropertiesFromVars $entry2 -vars $allvars -exclude $excludeProperties -WarningAction $warnaction -path $entry2._fullpath
                    
                }

                return $entry2
            }
            else {
                return $null
            }
        }
        else {
            $entry = $map.$split
        }
        if ($null -eq $entry) {
            break
        }
        if ($null -ne $entry -and $null -ne $entry.group) {
            $isGroup = $true
            break
        }
        $map = $entry
    }    

    #       }
}

<#
$global:seen = @{}
#> 
function Convert-PropertiesFromVars { 
    [CmdletBinding()]
    param($obj, $vars = @{}, [switch][bool]$strict, $exclude = @(), [int]$level = 0, $path = "") 
    if ("_vars" -notin $exclude) {
        $exclude += @("_vars")
    }
    #Measure-function  "$($MyInvocation.MyCommand.Name)" {
    $msg = " replacing vars in object '$path' : $obj"
    <#
    if ($global:seen[$path] -eq $null) {
        $global:seen[$path] = $obj
    } else {
        write-warning "processing path '$path' for the second time!"
    }
    #>
    write-verbose $msg.PadLeft($level + $msg.Length, ">")
    $exclude = @($exclude)
    if ($null -eq $vars) {
        throw "vars == NULL"
    }
    if ($obj -is [string]) {
        $replaced = Convert-Vars -text $obj -vars $vars
        return $replaced
    }
    elseif ($obj -is [System.Collections.IDictionary]) {
        $keys = _clone $obj.keys
        $keys = $keys | Sort-Object        
        foreach ($key in $keys) {
            if ($key -notin $exclude) {
                if ($obj[$key] -in $exclude) {
                    continue
                }
                $self = $obj
                try {
                    $obj[$key] = Convert-PropertiesFromVars $obj[$key] $vars -exclude ($exclude + @($obj)) -level ($level + 1) -path "$path.$key"
                }
                finally {
                    $self = $null
                }
                
            }
        }
        return $obj
    }
    elseif ($obj -is [Array]) {
        $clone = _clone $obj
        for ($i = 0; $i -lt $clone.length; $i++) {
            if ($clone[$i] -in $exclude) {
                continue
            }
            try {
                $clone[$i] = Convert-PropertiesFromVars $clone[$i] $vars -exclude ($exclude + @($clone)) -level ($level + 1) -path "$path[$i]"
            }
            catch {
                write-error "failed to replace properties for array object $($clone)[$i]: $($_.Exception.Message)"
            }
            finally {
            }
        }
        return $clone
    }    
    elseif ($strict) {
        throw "unsupported object"
       
    }
    return $obj
    
    #  }
}

#TODO: support multiple matches per line
function _replaceVarline ([Parameter(Mandatory = $true)]$text, $vars = @{}) {
    #Measure-function  "$($MyInvocation.MyCommand.Name)" {

    $r = $text
    if ($null -eq $vars) {
        throw "vars == NULL"
    }

    if (!($text.Contains("_")) -and !($text.Contains("{"))) { return $r }
    do {
        #each replace may insert a new variable reference in the string, so we need to iterate again
        $replaced = $false
        foreach ($kvp in $vars.GetEnumerator()) {
            $name = $kvp.key
            $val = $kvp.value

            if ($r -match "\{$name\}") {
                $r = $r -replace "\{$name\}", $val
                $replaced = $true
                break
            }
            # support also same placeholder as in template match
            elseif ($r -match "__$($name)__") {
                $r = $r -replace "__$($name)__", $val
                $replaced = $true
                break
            }
            elseif ($r -match "_$($name)_") {
                $r = $r -replace "_$($name)_", $val
                $replaced = $true
                break
            }
        }    
    } while ($replaced)

    return $r    
    #       }
}

#TODO: support multiple matches per line
function _ReplaceVarsAuto([Parameter(Mandatory = $true)]$__text) {
    #       Measure-function  "$($MyInvocation.MyCommand.Name)" {

    do {
        #each replace may insert a new variable reference in the string, so we need to iterate again
        $__replaced = $false
        $__matches = [System.Text.RegularExpressions.Regex]::Matches($__text, "\{(\?{0,1}[a-zA-Z0-9_.:]+?)\}")
        foreach ($__match in $__matches) {
            if ($__match.Success) {
                $__name = $__Match.Groups[1].Value
                $__orgname = $__name
                $__defaultifnull = $false
                if ($__name.startswith("?")) {
                    $__name = $__name.substring(1)
                    $__defaultifnull = $true
                }
                $__varpath = $__name 
                $__splits = $__name.split(".")
                $__splitstart = 1
                if (!($__varpath -match ":")) {
                    if ($__varpath.startswith("vars.")) {
                        $__varpath = "variable:" + $__splits[0]                 
                    }
                    else {
                        $__varpath = "cannot-reference-local-script-or-global-vars-without-namespace-prefix"
                    }
                }
                $__val = $null
                # this is a fragile thing. the module itself may define local vars that collide with map vars
                if (test-path "$__varpath") {
                    $__val = (get-item $__varpath).Value
                    for ($__i = $__splitstart; $__i -lt $__splits.length; $__i++) {
                        $__s = $__splits[$__i] 
                        $__val = $__val.$__s
                    }  
                }
                elseif (test-path "variable:self") {
                    $__selftmp = (get-item "variable:self").Value
                    $__val = $__selftmp
                    foreach ($__s in $__splits) {
                        $__val = $__val.$__s
                    }            
                }
                if ($null -ne $__val) {
                    $__text = $__text -replace "\{$([System.Text.RegularExpressions.Regex]::Escape($__orgname))\}", $__val
                    $__replaced = $true
                } 
                elseif ($__defaultifnull) {
                    $__text = $__text -replace "\{$([System.Text.RegularExpressions.Regex]::Escape($__orgname))\}", ""
                    $__replaced = $true                
                }
            }
        }
    }
    while ($__replaced)
    return $__text
    #         }
}

function convert-vars {
    [CmdletBinding()]
    param ([Parameter(Mandatory = $true)]$text, $vars = @{}, [switch][bool]$noauto = $false) 
    #     Measure-function  "$($MyInvocation.MyCommand.Name)" {
    $org = $text
    $text = @($text) | % { _replaceVarline $_ $vars }

    $originalself = $self
    try {
        # is this necessary if we're doing Convert-PropertiesFromVars twice? 
        if (!$noauto) {
            # _ReplaceVarsAuto uses $self global variable
            # if it is not set, use $vars as $self
            if ($null -eq $originalself) {
                $self = $vars
            }
            $text = @($text) | % { _ReplaceVarsAuto $_ }
        
            # also use $vars as $self if $self was passed
            if ($null -ne $originalself -and $vars -ne $originalself) {
                $self = $vars
                $text = @($text) | % { _ReplaceVarsAuto $_ }
            }        
        }

    
        $m = [System.Text.RegularExpressions.Regex]::Matches($text, "\{(\?{0,1}[a-zA-Z0-9_.:]+?)\}")
        if ($m.count -gt 0) {
            write-warning "missing variable '$($m[0].Groups[1].Value)' in '$text'"
            if ($WarningPreference -ne "SilentlyContinue") {
                $a = 0
            }
        }
        if ($org -ne $text) {
            write-verbose "replaced: $org -> $text"
        }
        return $text
    } finally { 
        $self = $originalself
    }
    #   }
}

function get-vardef ($text) {
 
    #  Measure-function  "$($MyInvocation.MyCommand.Name)" {
    $result = $null
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "__([a-zA-Z]+)__");
    if ($m.Count -gt 0) {
        $result = $m | % {
            $_.Groups[1].Value
        }
        return $result
    }

    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "_([a-zA-Z]+)_");
    if ($m.Count -gt 0) {
        $result = $m | % {
            $_.Groups[1].Value
        }
        return $result
    }

    return $null
    #}
}

function _MatchVarPattern ($text, $pattern) {
    #   Measure-function  "$($MyInvocation.MyCommand.Name)" {

    $result = $null
    $vars = get-vardef $pattern
    if ($null -eq $vars) {
        return $null 
    }
    $vars = @($vars)
    if ($vars.Length -eq 0) {
        
    }
    $regex = $pattern -replace "__[a-zA-Z]+__", "([a-zA-Z0-9]*)"    
    $regex = $regex -replace "_[a-zA-Z]+_", "([a-zA-Z0-9]*)"    
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "^$regex`$");
    
    if ($null -ne $m) {
        try {
            $result = $m | % {
                for ($i = 1; $i -lt $_.Groups.Count; $i++) {
                    $val = $_.Groups[$i].Value
                    $name = $vars[$i - 1]
                    if ($null -ne $name) {
                        return @{ $name = $val }
                    }
                    else {
                        Write-Warning "null name in vars??"
                    }
                }
            }
        } catch {
            throw
        }
    }
    return $result
    #}
}

new-alias Replace-Vars Convert-Vars -force
new-alias Replace-Properties Convert-PropertiesFromVars -force
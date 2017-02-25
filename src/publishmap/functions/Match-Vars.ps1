<#
    .PARAMETER simpleMode 
    for better performance. do not perform variable substitution based on self and root
    should still work for simpler scenarios

#>

function _clone($obj) {
    if ($obj -is [System.Collections.Specialized.OrderedDictionary]) {
        $copy = [ordered]@{}
        foreach($e in $obj.GetEnumerator()) {
            $copy.Add($e.Key, $e.Value)
        }

        return $copy
    }
    else {
        return $obj.Clone()
    }
}

function get-entry(
    [Parameter(mandatory=$true,Position=1)] $key,
    [Parameter(mandatory=$true,ValueFromPipeline=$true,Position=2)] $map,
    $excludeProperties = @("project"),
    [switch][bool] $simpleMode = $false) 
{
    $root = $map
    $parent = $null
    $entry = $null
    $splits=$key.split(".")
    for($i = 0; $i -lt $splits.length; $i++) {
        $split = $splits[$i]
        $parent = $entry
        if ($i -eq $splits.length-1) {
            $key = $split
            if ($map[$key] -ne $null) { 
               $entry = $map[$key] 
               $vars = @()
            }
            elseif ($key -eq "/" -or $key -eq "\") {
                $entry = $map
                $vars = @()
            } 
            else {     
                foreach($kvp in $map.GetEnumerator()) {
                    $pattern = $kvp.key
                    $vars = _MatchVarPattern $key "$pattern"
                    if ($vars -ne $null) {
                            $entry = $kvp.value   
                            break
                    }
                }
           }

           if ($entry -ne $null) {
             #TODO: should we use a deep clone
             $entry2 = _clone $entry
             if ($entry2 -is [Hashtable]) {
                $entry2._vars = $vars
             }             
             $warnaction = "SilentlyContinue"
             if ($simpleMode) { $warnaction = "Continue" }
             $entry2 = replace-properties $entry2 -vars $vars -exclude $excludeProperties -WarningAction $warnaction
             if (!$simpleMode) {
                 # replace properties based on self values
                 $entry2 = replace-properties $entry2 -vars $map -exclude $excludeProperties -WarningAction "SilentlyContinue"
                 # replace properties based on root values
                 $entry2 = replace-properties $entry2 -vars $root -exclude $excludeProperties  
             }
             return $entry2
           }

           return $entry
        }
        else {
            $entry = $map.$split
        }
        if ($entry -eq $null) {
            break
        }
        if ($entry -ne $null -and $entry.group -ne $null) {
            $isGroup = $true
            break
        }
        $map = $entry
    }    

   
}

function Convert-PropertiesFromVars { 
[CmdletBinding()]
param($obj, $vars = @{}, [switch][bool]$strict, $exclude = @()) 

    $exclude = @($exclude)
    if ($vars -eq $null) { throw "vars == NULL"}
    if ($obj -is [string]) {
        $replaced = replace-vars -text $obj -vars $vars
        return $replaced
    }
    elseif ($obj -is [System.Collections.IDictionary]) {
        $keys = _clone $obj.keys
        $keys = $keys | Sort-Object        
        foreach($key in $keys) {
            if ($key -notin $exclude) {
                if ($obj[$key] -in $exclude) {
                    continue
                }
                $self = $obj
                try {
                    $obj[$key] = replace-properties $obj[$key] $vars -exclude ($exclude + @($obj))
                }
                finally {
                    $self = $null
                }
                
            }
        }
        return $obj
    }
    elseif ($obj -is [Array]) {
        $obj = _clone $obj
         for($i = 0; $i -lt $obj.length; $i++) {
            if ($obj[$i] -in $exclude) {
                continue
            }
            try {
                $obj[$i] = replace-properties $obj[$i] $vars -exclude ($exclude + @($obj))
            }
            finally {
            }
        }
    }    
    elseif ($strict) {
        throw "unsupported object"
       
    }

    return $obj
}

#TODO: support multiple matches per line
function _replaceVarline ([Parameter(Mandatory=$true)]$text, $vars = @{}) {
    $r = $text
    if ($vars -eq $null) { throw "vars == NULL"}

    do {
        #each replace may insert a new variable reference in the string, so we need to iterate again
        $replaced = $false
        foreach($kvp in $vars.GetEnumerator()) {
            $name = $kvp.key
            $val = $kvp.value

            if ($r -match "\{$name\}") {
                $r = $r -replace "\{$name\}",$val
                $replaced = $true
                break
            }
            # support also same placeholder as in template match
            elseif ($r -match "__$($name)__") {
                $r = $r -replace "__$($name)__",$val
                $replaced = $true
                break
            }
            elseif ($r -match "_$($name)_") {
                $r = $r -replace "_$($name)_",$val
                $replaced = $true
                break
            }
        }    
    } while ($replaced)

    return $r    
}

#TODO: support multiple matches per line
function _ReplaceVarsAuto([Parameter(Mandatory=$true)]$__text)  {
    
    do {
    #each replace may insert a new variable reference in the string, so we need to iterate again
    $__replaced = $false
    $__matches = [System.Text.RegularExpressions.Regex]::Matches($__text, "\{(\?{0,1}[a-zA-Z0-9_.:]+?)\}")
    foreach($__match in $__matches) {
        if ($__match.Success) {
            $__name = $__Match.Groups[1].Value
            $__orgname = $__name
            $__defaultifnull = $false
            if ($__name.startswith("?")) {
                $__name= $__name.substring(1)
                $__defaultifnull = $true
            }
            $__varpath = $__name 
            $__splits = $__name.split(".")
            $__splitstart = 1
            if (!($__varpath -match ":")) {
                    if ($__varpath.startswith("vars.")) {
                        $__varpath = "variable:" + $__splits[0]                 
                    } else {
                        $__varpath = "cannot-reference-local-script-or-global-vars-without-namespace-prefix"
                    }
            }
            $__val = $null
            # this is a fragile thing. the module itself may define local vars that collide with map vars
            if (test-path "$__varpath") {
                $__val = (get-item $__varpath).Value
                for($__i = $__splitstart; $__i -lt $__splits.length; $__i++) {
                    $__s = $__splits[$__i] 
                    $__val = $__val.$__s
                }  
            }
            elseif (test-path "variable:self") {
                $__selftmp = (get-item "variable:self").Value
                $__val = $__selftmp
                foreach($__s in $__splits) {
                    $__val = $__val.$__s
                }            
            }
            if ($__val -ne $null) {
                    $__text = $__text -replace "\{$([System.Text.RegularExpressions.Regex]::Escape($__orgname))\}",$__val
                    $__replaced = $true
            } 
            elseif ($__defaultifnull) {
                $__text = $__text -replace "\{$([System.Text.RegularExpressions.Regex]::Escape($__orgname))\}",""
                $__replaced = $true                
            }
        }
    }
    }
    while ($__replaced)
    return $__text
}

function convert-vars([Parameter(Mandatory=$true)]$text, $vars = @{}, [switch][bool]$noauto = $false) {
    $text = @($text) | ForEach { _replaceVarline $_ $vars }

    $originalself = $self
    try {
    # is this necessary if we're doing replace-properties twice? 
    if (!$noauto) {
        # _ReplaceVarsAuto uses $self global variable
        # if it is not set, use $vars as $self
        if ($originalself -eq $null) {
            $self = $vars
        }
        $text = @($text) | ForEach { _ReplaceVarsAuto $_ }
        
        # also use $vars as $self if $self was passed
        if ($originalself -ne $null -and $vars -ne $originalself) {
            $self = $vars
            $text = @($text) | ForEach { _ReplaceVarsAuto $_ }
        }        
    }

    
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "\{(\?{0,1}[a-zA-Z0-9_.:]+?)\}")
    if ($m.count -gt 0) {
        write-warning "missing variable '$($m[0].Groups[1].Value)'"
        if ($WarningPreference -ne "SilentlyContinue") {
            $a = 0
        }
    }
    return $text
    } finally { 
        $self = $originalself
    }
}

function get-vardef ($text) {
    $result = $null
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "__([a-zA-Z]+)__");
    if ($m -ne $null) {
        $result = $m | ForEach {
            $_.Groups[1].Value
        }
        return $result
    }

    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "_([a-zA-Z]+)_");
    if ($m -ne $null) {
        $result = $m | ForEach {
            $_.Groups[1].Value
        }
        return $result
    }

    return $null
}

function _MatchVarPattern ($text, $pattern) {
    $result = $null
    $vars = @(get-vardef $pattern)
    if ($vars -eq $null) { return $null }
    $regex = $pattern -replace "__[a-zA-Z]+__","([a-zA-Z0-9]*)"    
    $regex = $regex -replace "_[a-zA-Z]+_","([a-zA-Z0-9]*)"    
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "^$regex`$");
    
    if ($m -ne $null) {
        $result = $m | ForEach {
            for($i = 1; $i -lt $_.Groups.Count; $i++) {
                $val = $_.Groups[$i].Value
                $name = $vars[$i-1]
                return @{ $name = $val }
            }
        }
    }

    return $result
}

new-alias Replace-Vars Convert-Vars -force
new-alias Replace-Properties Convert-PropertiesFromVars -force
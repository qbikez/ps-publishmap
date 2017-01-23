function get-entry(
    [Parameter(mandatory=$true,Position=1)] $key,
    [Parameter(mandatory=$true,ValueFromPipeline=$true,Position=2)] $map,
    $excludeProperties = @("project")) 
{
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
           else {     
            foreach($kvp in $map.GetEnumerator()) {
                $pattern = $kvp.key
                $vars = match-varpattern $key "$pattern"
                if ($vars -ne $null) {
                        $entry = $kvp.value   
                        break
                }
            }
           }

           if ($entry -ne $null) {
             #TODO: should we use a deep clone
             $entry2 = $entry.Clone()
             $entry2._vars = $vars
             $entry2 = replace-properties $entry2 -vars $vars -exclude $excludeProperties     
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

function replace-properties($obj, $vars = @{}, [switch][bool]$strict, $exclude = @()) {
    $exclude = @($exclude)
    if ($vars -eq $null) { throw "vars == NULL"}
    if ($obj -is [string]) {
        $replaced = replace-vars -text $obj -vars $vars
        return $replaced
    }
    elseif ($obj -is [System.Collections.IDictionary]) {
        $keys = $obj.keys.Clone()
        $keys = $keys | sort
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
        $obj = $obj.Clone()
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
function _replace-varline ([Parameter(Mandatory=$true)]$text, $vars = @{}) {
    $r = $text
    if ($vars -eq $null) { throw "vars == NULL"}
    foreach($kvp in $vars.GetEnumerator()) {
        $name = $kvp.key
        $val = $kvp.value

        if ($text -match "\{$name\}") {
            $r = $r -replace "\{$name\}",$val
        }
        # support also same placeholder as in template match
        elseif ($text -match "__$($name)__") {
            $r = $r -replace "__$($name)__",$val
        }
        elseif ($text -match "_$($name)_") {
            $r = $r -replace "_$($name)_",$val
        }
    }    

    return $r    
}

#TODO: support multiple matches per line
function _replace-varauto([Parameter(Mandatory=$true)]$text)  {
    $matches = [System.Text.RegularExpressions.Regex]::Matches($text, "\{(\?{0,1}[a-zA-Z0-9_.:]+?)\}")
    foreach($match in $matches) {
        if ($match.Success) {
            $name = $Match.Groups[1].Value
            $orgname = $name
            $defaultifnull = $false
            if ($name.startswith("?")) {
                $name= $name.substring(1)
                $defaultifnull = $true
            }
            $varpath = $name 
            $splits = $name.split(".")
            $splitstart = 1
            if (!($varpath -match ":")) {
                    $varpath = "variable:" + $splits[0]                 
            }
            $val = $null
            if (test-path "$varpath") {
                $val = (get-item $varpath).Value
                for($i = $splitstart; $i -lt $splits.length; $i++) {
                    $s = $splits[$i] 
                    $val = $val.$s
                }  
            }
            elseif (test-path "variable:self") {
                $selftmp = (get-item "variable:self").Value
                $val = $selftmp
                foreach($s in $splits) {
                    $val = $val.$s
                }            
            }
            if ($val -ne $null) {
                    $text = $text -replace "\{$([System.Text.RegularExpressions.Regex]::Escape($orgname))\}",$val
            } 
            elseif ($defaultifnull) {
                $text = $text -replace "\{$([System.Text.RegularExpressions.Regex]::Escape($orgname))\}",""
            }
        }
    }
    return $text
}

function convert-vars ([Parameter(Mandatory=$true)]$text, $vars = @{}, [switch][bool]$noauto = $false) {
    $text = @($text) | % { _replace-varline $_ $vars }
    if ($self -eq $null) {
        $self = $vars
    }
    if (!$noauto) {
        $text = @($text) | % { _replace-varauto $_ }
    }

    
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "\{(\?{0,1}[a-zA-Z0-9_.:]+?)\}")
    if ($m.count -gt 0) {
        write-warning "missing variable '$($m[0].Groups[1].Value)'"
    }
    return $text
}

function get-vardef ($text) {
    $result = $null
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "__([a-zA-Z]+)__");
    if ($m -ne $null) {
        $result = $m | % {
            $_.Groups[1].Value
        }
        return $result
    }

    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "_([a-zA-Z]+)_");
    if ($m -ne $null) {
        $result = $m | % {
            $_.Groups[1].Value
        }
        return $result
    }

    return $null
}

function match-varpattern ($text, $pattern) {
    $result = $null
    $vars = @(get-vardef $pattern)
    if ($vars -eq $null) { return $null }
    $regex = $pattern -replace "__[a-zA-Z]+__","([a-zA-Z0-9]*)"    
    $regex = $regex -replace "_[a-zA-Z]+_","([a-zA-Z0-9]*)"    
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "^$regex`$");
    
    if ($m -ne $null) {
        $result = $m | % {
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
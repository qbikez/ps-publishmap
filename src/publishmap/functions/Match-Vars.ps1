function get-entry(
    [Parameter(mandatory=$true)] $key,
    [Parameter(mandatory=$true)] $map,
    $excludeProperties = @()) 
{
   $entry = $null
   if ($map[$key] -ne $null) { 
       $entry = $map[$key] 
       $vars = @()
   }
   else {     
    foreach($kvp in $map.GetEnumerator()) {
        $pattern = $kvp.key
        $vars = match-varpattern $key $pattern
        if ($vars -ne $null) {
                $entry = $kvp.value   
                break
        }
    }
   }

   if ($entry -ne $null) {
     $entry = $entry.Clone()
     $entry._vars = $vars
     $entry = replace-properties $entry -vars $vars -exclude $excludeProperties     
   }

   return $entry
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
        elseif ($text -match "_$($name)_") {
            $r = $r -replace "_$($name)_",$val
        }
    }    
    return $r    
}

#TODO: support multiple matches per line
function _replace-varauto([Parameter(Mandatory=$true)]$text)  {
    if ($text -match "\{([a-zA-Z0-9_.:]+?)\}") {
        $name = $Matches[1]
        $varpath = $name
        $splits = $name.split(".")
        if (!($varpath -match ":")) { 
            $varpath = "variable:" + $splits[0]                 
        }
        $val = $null
        if (test-path "$varpath") {
            $val = (get-item $varpath).Value
            for($i = 1; $i -lt $splits.length; $i++) {
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
                $text = $text -replace "\{$name\}",$val
        }
    }
    return $text
}

function convert-vars ([Parameter(Mandatory=$true)]$text, $vars = @{}, [switch][bool]$noauto = $false) {
    $text = @($text) | % { _replace-varline $_ $vars }
    
    if (!$noauto) {
        $text = @($text) | % { _replace-varauto $_ }
    }
    return $text
}

function get-vardef ($text) {
    $result = $null
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, "_([a-zA-Z]+)");
    if ($m -ne $null) {
        $result = $m | % {
            $_.Groups[1].Value
        }
    }

    return $result
}

function match-varpattern ($text, $pattern) {
    $result = $null
    $vars = @(get-vardef $pattern)
    if ($vars -eq $null) { return $null }
    $regex = $pattern -replace "_[a-zA-Z]+_","([a-zA-Z0-9]*)"    
    $m = [System.Text.RegularExpressions.Regex]::Matches($text, $regex);
    
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

new-alias Replace-Vars Convert-Vars
function get-entry(
    [Parameter(mandatory=$true)] $key,
    [Parameter(mandatory=$true)] $map,
    $excludeProperties = @()) {
   if ($map[$key] -ne $null) { return $map[$key] }     
   foreach($kvp in $map.GetEnumerator()) {
       $pattern = $kvp.key
       $m = match-varpattern $key $pattern
       if ($m -ne $null) {
            $entry = $kvp.value   
            break;
       }
   }

   if ($entry -ne $null) {
     $entry = $entry.Clone()
     $entry = replace-properties $entry $m -exclude $excludeProperties
     $entry.vars = $m  
   }

   return $entry
}

function replace-properties($obj, $vars = @{}, [switch][bool]$strict, $exclude = @()) {
    if ($obj -is [string]) {
        return replace-vars $obj $vars
    }
    elseif ($obj -is [System.Collections.IDictionary]) {
        $keys = $obj.keys.Clone()
        foreach($key in $keys) {
            if ($key -notin $exclude) {
                $obj[$key] = replace-properties $obj[$key] $vars -exclude $exclude
            }
        }
        return $obj
    }
    elseif ($strict) {
        throw "unsupported object"
    }

    return $obj
}

#TODO: support multiple matches per line
function _replace-varline ($text, $vars = @{}) {
    $r = $text
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
function _replace-varauto($text)  {
    if ($text -match "\{([a-zA-Z0-9_:]+?)\}") {
        $name = $Matches[1]
        $varpath = $name
        if (!$varpath -match ":") { $varpath = "variable:" + $varpath }
        if (test-path "$varpath") {
            $val = (get-item $varpath).Value
            $text = $text -replace "\{$name\}",$val
        }
    }
    return $text
}

function replace-vars ($text, $vars = @{}, [switch][bool]$noauto = $false) {
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
    $vars = get-vardef $pattern
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
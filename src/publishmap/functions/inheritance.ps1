
function inherit-properties($from, $to, $exclude = @(), [switch][bool] $valuesOnly) {
    if ($from -is [System.Collections.IDictionary]) {
    }
    else {
        $from = $from.psobject.properties | % { $d = @{} } { $d[$_.name] = $_.value } { $d }
    }
    foreach($key in $from.keys) {
            $shouldExclude = $false 
        if ($key -in $exclude) { $shouldExclude = $true }
        if (@($exclude | ? { $key -match "^$_$" }).Count -gt 0) { $shouldExclude = $true }
        if ($from[$key] -is [System.Collections.IDictionary] -and $valuesOnly) { $shouldExclude = $true }

        if (!$shouldExclude) {
            add-property $to -name $key -value $from[$key] 
        }
    }
    
}

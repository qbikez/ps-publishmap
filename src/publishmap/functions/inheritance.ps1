
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


function inherit-globalsettings($proj, $settings) {
    
    if ($settings -ne $null) {
        write-verbose "inheriting global settings to $($proj._fullpath). strip=$stripsettingswrapper"
        $stripsettingswrapper = $settings._strip
                if ($stripsettingswrapper -ne $null -and $stripsettingswrapper) {
                    $null = add-properties $proj $settings -ifNotExists -merge
                }
                else {
                    $null = add-property $proj "settings" $settings -ifNotExists -merge
                }
            }
}
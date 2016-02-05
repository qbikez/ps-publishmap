
function inherit-properties($from, $to, $exclude = @()) {
    if ($from -is [System.Collections.IDictionary]) {
        foreach($key in $from.keys) {
            if ($to.($key) -eq $null -and $key -notin $exclude) {
                add-property $to -name $key -value $from[$key]
            }
        }
    }
    else {
        foreach($prop in $from.psobject.properties) {
            if ($to.($prop.name) -eq $null -and $prop.Name -notin $exclude) {
                add-property $to -name $prop.name -value $prop.value
            }
        }
    }
}

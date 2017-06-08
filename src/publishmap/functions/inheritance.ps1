<#

.PARAMETER valuesOnly
Inherit only value types, do not inherit dictionaries (helps prevent infinite inheritance loop)

#>
function Add-InheritedProperties($from, $to, $exclude = @(), [switch][bool] $valuesOnly) {
   # Measure-function  "$($MyInvocation.MyCommand.Name)" {

        if ($from -is [System.Collections.IDictionary]) {
        }
        else {
            $from = $from.psobject.properties | % { $d = @{} } { $d[$_.name] = $_.value } { $d }
        }
        $from = $from.getenumerator( ) | % { $h = @{} } {
            $key = $_.key
            $value = $_.value
            $shouldExclude = $false 
            if ($key -in $exclude) {
                $shouldExclude = $true 
            }
            if (@($exclude | ? { $key -match "^$_$" }).Count -gt 0) {
                $shouldExclude = $true 
            }
          
            if ($value -is [System.Collections.IDictionary]) {
                if ($valuesOnly) {
                    $shouldExclude = $true 
                }
                else {
                    $newvalue = copy-hashtable $value
                    $value = $newvalue
                }
            }
            if (!$shouldExclude) {
                $h[$key] = $value    
            }
        } { $h } 
    
        if ($null -ne $from) {
            try {
                $null = add-properties -object $to -props $from -merge -ifNotExists
            } catch {
                throw "failed to inherit properties:$($_.Exception.Message)`r`nfrom:`r`n$($from | format-table | out-string)`r`nto:`r`n$($to | format-table | out-string)"
            }
        
        }
        <# foreach($key in $from.keys) {

        $value = $from[$key] 

        if ($value -is [System.Collections.IDictionary]) {
            if ($valuesOnly) {
                $shouldExclude = $true 
            }
            else {
                $value = $value.Clone()
            }
         }

        if (!$shouldExclude) {
            add-property $to -name $key -value $value
        }
    }
    #>
 #   }
}


function Add-GlobalSettings($proj, $settings) {
 #   Measure-function  "$($MyInvocation.MyCommand.Name)" {

        if ($null -ne $settings) {
            write-verbose "inheriting global settings to $($proj._fullpath). strip=$stripsettingswrapper"
            $stripsettingswrapper = $settings._strip
            if ($null -ne $stripsettingswrapper -and $stripsettingswrapper) {
                $null = inherit-properties -from $settings -to $proj -ifNotExists -merge -exclude "_strip"
            }
            else {
                $null = add-property $proj "settings" $settings -ifNotExists -merge
            }
        }
#    }
}

New-Alias -Name Inherit-Properties -Value Add-InheritedProperties -Force
New-Alias -Name Inherit-GlobalSettings -Value Add-GlobalSettings -Force 
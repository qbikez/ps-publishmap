[cmdletbinding()]
param($maps = $null, [switch][bool] $silent=$true)

write-verbose "processing publishmap..."

. "$PSScriptRoot/functions/object-properties.ps1"
. "$PSScriptRoot/functions/inheritance.ps1"
. "$PSScriptRoot/functions/process-map.ps1"

$global:publishmap = $null

if ($maps -ne $null) {
    $maps = @($maps)
}
else {
    $maps = gci $PSScriptRoot -filter "publishmap.*.config.ps1"
}

$publishmap = @{}


foreach($m in $maps) {
    $publishmap += process-mapfile $m
}

$global:publishmap = $publishmap
$global:pmap = $global:publishmap 


write-verbose "processing publishmap... DONE"

return $publishmap

#$globalProfiles = @()
#$globalProfiles += $publishmap.ne.global_profiles

#foreach($profName in $globalProfiles.Keys) {
#    if ($profName -match "__XX__") {      
#    }
#}
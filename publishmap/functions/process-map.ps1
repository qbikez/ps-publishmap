function import-map {
    [cmdletbinding()]
    param([Parameter(Mandatory = $true)] $maps)
    
    if ($maps -is [System.Collections.IDictionary] ) {
        return import-mapobject $maps
    }    
    else {
        return import-mapfile $maps
    }
}

function import-mapfile {
    [cmdletbinding()]
    param([Parameter(Mandatory = $true)] $maps)
    #  Measure-function  "$($MyInvocation.MyCommand.Name)" {

    write-verbose "processing publishmap..."

    if ($null -ne $maps) {
        $maps = @($maps)
    }
        
    $publishmap = @{}

    foreach ($m in $maps) {
        $publishmap += import-singlemapfile $m
    }

    write-verbose "processing publishmap... DONE"

    return $publishmap
    #  }
}


function import-mapobject { 
    [cmdletbinding()]
    param([Parameter(Mandatory = $true)] $map) 
    $pmap = @{}
    
    $pmap = import-genericgroup $map ""   
    #  Measure-function  "add-metaproperties" {
    $pmap = add-metaproperties $pmap ""
    #   }
    return $pmap
}

function import-singlemapfile($file) {
    $fullname = $file
    if ($null -ne $fullname.FullName) {
        $Fullname = $Fullname.FullName 
    }
    $map = & "$FullName"
    
    #$publishmap_obj = ConvertTo-Object $publishmap
    $pmap = import-mapobject $map

    return $pmap
}

<#
.Synopsis
Applies `_inherit_from` chains between sibling entries of a group.
#>
function Add-InheritedFromSiblings($entry, $siblings) {
    $inheritFrom = $entry._inherit_from
    if ($null -eq $inheritFrom) { return }
    if (!$siblings.Contains($inheritFrom)) {
        write-verbose "cannot find inheritance base '$inheritFrom' for '$($entry._fullpath)'"
        return
    }

    $hierarchy = @()
    $cur = $entry
    while ($null -ne $cur._inherit_from -and !$entry.Contains("_inherited_from")) {
        $hierarchy += , $cur
        $cur = $siblings[$cur._inherit_from]
    }
    for ($i = $hierarchy.Count - 1; $i -ge 0; $i--) {
        $cur = $hierarchy[$i]
        if ($cur.Contains("_inherited_from")) { continue }
        $base = $siblings[$cur._inherit_from]
        Add-InheritedProperties -from $base -to $cur -valuesOnly -exclude @("_inherit_from", "_inherited_from")
        $null = add-property $cur -name _inherited_from -value $cur._inherit_from
    }
}

function import-genericgroup($group,
    $fullpath,
    $settings = $null,
    $settingskey = "settings",
    $specialkeys = @("settings", "global_profiles")
) {
    Write-Verbose "processing map path $fullpath"

    # only direct children inherit settings
    $childsettings = $null
    if ($group.Contains($settingskey)) {
        $childsettings = $group[$settingskey]
    }

    foreach ($projk in @($group.Keys)) {
        if ($projk -in $specialkeys) {
            continue
        }
        $subgroup = $group[$projk]
        if (!($subgroup -is [System.Collections.IDictionary])) {
            continue
        }

        Add-InheritedFromSiblings $subgroup $group
        Add-InheritedProperties -from $group -to $subgroup -valuesOnly
        if ($null -ne $settings) {
            Add-GlobalSettings $group $settings
        }
        $null = import-genericgroup $subgroup "$fullpath.$projk" -settings $childsettings -settingskey $settingskey -specialkeys $specialkeys
    }

    if ($null -ne $settings) {
        Add-GlobalSettings $group $settings
    }

    return $group
}

function add-metaproperties
{
    param($group, $fullpath, $specialkeys = @("settings", "global_prof1iles"))

    if ($group -isnot [System.Collections.IDictionary]) {
        return
    }
    write-verbose "adding meta properties to '$fullpath'"        
    $splits = $fullpath.split('.')
    $level = $splits.length - 1
    
    $null = $group | add-property -name _level -value $level
    $null = $group | add-property -name _fullpath -value $fullpath.trim('.')
    if ($splits.length -gt 0) {
        $null = $group | add-property -name _name -value $splits[$splits.length - 1]
    }
        
    #$keys = @{}
    $keys = get-propertynames $group
        
    foreach ($projk in $keys) {
        #do not process special global settings
        if ($projk -in $specialkeys) {
            continue
        }
        if ($group.$projk -is [System.Collections.IDictionary]) {
            $path = "$fullpath.$projk"            
            $null = add-metaproperties $group.$projk $path -specialkeys $specialkeys
        }
    }
  
    return $group
    
}

<# 
function import-mapgroup(
    $publishmapgroup, $groupk,     
    $settings = $null,
    $stripsettingswrapper = $false
) {
    Write-Verbose "processing map $groupk"
   
    $keys = get-propertynames $publishmapgroup
    
    $null = add-property $publishmapgroup "level" 1
    $null = add-property $publishmapgroup -name fullpath -value "$groupk"
    
    $group = $publishmapgroup
    $result = {}
    foreach($projk in $keys) {
            #do not process special global settings
            if ($projk -in "settings","global_profiles") {
                continue
            }
            $proj = $group.$projk            
            $r = import-mapproject $proj $projk $level
            
            $null = add-property $proj "level" 2
            $null = add-property $proj -name fullpath  -value "$groupk.$projk"
                       
        }

    return $publishmapgroup
}

#>
<#

#>

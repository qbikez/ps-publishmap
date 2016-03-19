function import-map {
    [cmdletbinding()]
    param([Parameter(Mandatory=$true)] $maps)
    
    if ($maps -is [System.Collections.IDictionary] ) {
        return import-mapobject $maps
    }    
    else {
        return import-mapfile $maps
    }
}

function import-mapfile {
    [cmdletbinding()]
    param([Parameter(Mandatory=$true)] $maps)

    write-verbose "processing publishmap..."

    if ($maps -ne $null) {
        $maps = @($maps)
    }
        
    $publishmap = @{}

    foreach($m in $maps) {
        $publishmap += import-singlemapfile $m
    }

    write-verbose "processing publishmap... DONE"

    return $publishmap
}


function import-mapobject { 
[cmdletbinding()]
param([Parameter(Mandatory=$true)] $map) 
   $pmap = @{}
    
   $pmap = import-genericgroup $map ""   
   $pmap = add-metaproperties $pmap ""
   return $pmap
}

function import-singlemapfile($file) {
    $fullname = $file
    if ($fullname.FullName -ne $null) { $Fullname =$Fullname.FullName }
    $map = & "$FullName"
    
    #$publishmap_obj = ConvertTo-Object $publishmap
    $pmap = import-mapobject $map

   return $pmap
}


function import-genericgroup($group,
    $fullpath, 
    $settings = $null,
    $settingskey = "settings",
    $specialkeys = @("settings", "global_profiles")
) {
    Write-Verbose "processing map path $fullpath"
   
    $result = {}        

    $onelevelsettingsinheritance = $true

    $childsettings = $null 
    #get settings for children
    if ($group.$settingskey -ne $null) {
        $childsettings = $group.$settingskey
    } else {
        if (!$onelevelsettingsinheritance) {
            $childsettings = $settings
        }
    }
    
    $keys = get-propertynames $group
    foreach($projk in $keys) {
        #do not process special global settings
        if ($projk -in $specialkeys) {
            continue
        }
        $subgroup = $group.$projk
        if (!($subgroup -is [System.Collections.IDictionary])) {
            continue
        }
        $path = "$fullpath.$projk"            


        inherit-properties -from $group -to $subgroup -valuesonly
        if ($settings -ne $null) {
                inherit-globalsettings $group $settings
        }
        $r = import-genericgroup $subgroup $path -settings $childsettings -settingskey $settingskey -specialkeys $specialkeys
    }


    if ($settings -ne $null) {
        inherit-globalsettings $group $settings
        
      <#  $keys = get-propertynames $group
        foreach($projk in $keys) {
            $subgroup = $group.$projk
            if ($projk -in $specialkeys) {
                continue
            }
            if (!($subgroup -is [System.Collections.IDictionary])) {
                continue
            }
            inherit-properties -from $group -to $subgroup -valuesonly
        }
        #>
    }
    
    

    return $map
}

function add-metaproperties($group, $fullpath, $specialkeys = @("settings", "global_profiles")
) {
    if ($group -isnot [System.Collections.IDictionary]) {
        return
    }
    $level = $fullpath.split('.').length - 1
    
    $null = $group | add-property -name _level -value $level
    $null = $group | add-property -name _fullpath -value $fullpath.trim('.')

      $keys = get-propertynames $group

        
    foreach($projk in $keys) {
     #do not process special global settings
        if ($projk -in $specialkeys) {
                continue
        }
        $path = "$fullpath.$projk"
        $null = add-metaproperties $group.$projk $path -specialkeys $specialkeys
    }
  
    return $group
}

function import-mapgroup(
    $publishmapgroup, $groupk,     
    $settings = $null,
    $stripsettingswrapper = $false
) {
    Write-Verbose "processing map $groupk"
   
    $globalProffiles = $publishmapgroup.global_profiles
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


<#

#>

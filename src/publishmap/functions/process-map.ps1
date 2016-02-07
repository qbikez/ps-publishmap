function import-mapfile {
    [cmdletbinding()]
    param($maps = $null)

    write-verbose "processing publishmap..."

    $global:publishmap = $null

    if ($maps -ne $null) {
        $maps = @($maps)
    }
    else {
        $maps = gci . -filter "publishmap.*.config.ps1"
    }

    $publishmap = @{}

    foreach($m in $maps) {
        $publishmap += import-singlemapfile $m
    }

    $global:publishmap = $publishmap
    $global:pmap = $global:publishmap 

    write-verbose "processing publishmap... DONE"

    return $publishmap
}


function import-mapobject { 
[cmdletbinding()]
param($map) 
   $pmap = @{}
    
   $pmap = import-genericgroup $map ""   
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
   
    $keys = get-propertynames $group
    $level = $fullpath.split('.').length
    
    
   
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
                    
            $r = import-genericgroup $subgroup $path -settings $childsettings -settingskey $settingskey -specialkeys $specialkeys

    }

    $null = $group | add-property -name _level -value $level
    $null = $group | add-property -name _fullpath -value $fullpath.trim('.')

    if ($settings -ne $null) {
        inherit-globalsettings $group $settings 
    }
    
    

    return $map
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
function import-mapproject($proj) {
            #proj = viewer,website,drmserver,vfs, etc.
            #$proj = $group[$projk]
            
            inherit-globalsettings $proj $settings $stripsettingswrapper
            
            $profiles = @()
            if ($proj.profiles -ne $null) {
                $profiles += get-propertynames $proj.profiles
            }
            if ($globalProffiles -ne $null) {
                $profiles += get-propertynames $globalProffiles
            }
            $profiles = $profiles | select -Unique
            #write-host "$groupk.$projk"
                
            foreach($profk in $profiles) {
                  check-profileName $proj $profk            
                  $prof = $proj.profiles.$profk
                  import-mapprofile $prof -parent $proj     
                  $null = add-property $proj -name $profk -value $prof
            }
}

function import-mapprofile($prof, $parent) {
   # make sure all profiles exist
                
                #inherit settings from project
                inherit-properties -from $parent -to $prof -exclude (@("profiles") + $profiles + @("level","fullpath"))

                #inherit global profile settings
                if ($globalProffiles -ne $null -and $globalProffiles.$profk -ne $null -and $prof.inherit -ne $false -and $parent.inherit -ne $false) {
                    # inherit project-specific settings 
                    #foreach($prop in $globalProffiles.$profk.psobject.properties | ? { $_.name -eq $projk }) {
                    #    if ($prop.name -eq $projk) {
                    $global = $globalProffiles.$profk
                    inherit-properties -from $global -to $prof
                    #    }
                    #}                    
                    # inherit generic settings
                    inherit-properties -from $settings -to $prof                   
                }
                $null = add-property $prof "_level" 3

                #fill meta properties
                $null = add-property $prof -name _parent -value $parent
                #add-property $prof -name fullpath  -value "$groupk.$projk.$profk"
                $null = add-property $prof -name _name -value "$profk"               
                
}
<#

#>
function get-profile($name, $map = $null) {
            $pmap = $map
            if ($map -eq $null) {
                $pmap = $global:pmap
            }

            $profName = $name
            $splits = $profName.Split('.')

            $map = $pmap
            $entry = $null
            $parent = $null
            $isGroup = $false
            foreach($split in $splits) {
                $parent = $entry
                $entry = get-entry $split $map -excludeProperties @("project")             
                if ($entry -eq $null) {
                    break
                }
                if ($entry -ne $null -and $entry.group -ne $null) {
                    $isGroup = $true
                    break
                }
                $map = $entry
            }    
            $profile = $entry
            if ($profile -eq $null)  {
                if ($splits[1] -eq "all") {
                    $isGroup = $true
                    $profile = $parent
                    break
                }
                else {
                    #write-host "unknown profile $profName"
                    return $null
                }
            }

            return new-object -Type pscustomobject -Property @{
                Profile = $profile
                IsGroup = $isGroup
                Project = $splits[0]
                Group = $splits[1]
                TaskName = $splits[2]
            }
}


function check-profileName($proj, $profk) {
    $prof = $proj.profiles.$profk
                if ($prof -eq $null) {
                    
                    if ($proj.inherit -ne $false) {
                        $prof = @{}
                        if ($proj.profiles -eq $null) {
                            $null = add-property $proj -name "profiles" -value @{}
                        }
                        $null = add-property $proj.profiles -name $profk -value $prof
                    }
                    else {
                        continue
                    }
                }
}
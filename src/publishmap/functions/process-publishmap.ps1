function import-publishmap {
    [cmdletbinding()]
    param([Parameter(Mandatory=$false)] $maps = $null)
    
    if ($maps -is [System.Collections.IDictionary] ) {
        return import-publishmapobject $maps
    }    
    else {
        return import-publishmapfile $maps
    }
}

function import-publishmapfile {
        [cmdletbinding()]
    param($maps)
     write-verbose "processing publishmap..."

    $global:publishmap = $null

    if ($maps -ne $null) {
        $maps = @($maps)
    }
    else {
        $maps = gci . -filter "publishmap.*.config.ps1"
    }

    $publishmap = @{}

    foreach($file in $maps) {
        try {
            $fullname = $file
            if ($fullname.FullName -ne $null) { $Fullname =$Fullname.FullName }
            $map = & "$FullName"
        
            #$publishmap_obj = ConvertTo-Object $publishmap
            $pmap = import-publishmapobject $map
            $publishmap += $pmap
        } catch {
            write-error "failed to import map file '$file'"
            throw
        }
    }

    $global:publishmap = $publishmap
    $global:pmap = $global:publishmap 

    write-verbose "processing publishmap... DONE"

    return $publishmap
}

function import-publishmapobject {
    [cmdletbinding()]
    param($map) 
    
    $map = prepare-publishmap $map
    $pmap = import-mapobject $map
    $pmap = process-publishmap $pmap
    
    return $pmap           
}

function prepare-publishmap($map) {
    foreach($groupk in get-propertynames $map) {
        if ($map.$groupk.global_profiles -ne $null) {
            $settings = @{     
                profiles = $map.$groupk.global_profiles 
                _strip = $true
            } 
            $null = add-property $map.$groupk -name "settings" -value $settings -merge
        }
    }
    return $map
}

function process-publishmap($map) {    
    foreach($groupk in get-propertynames $map) {
        # remove generated properties from top-level
        if ($groupk.startswith("_")) {
            $map.Remove($groupk)
            continue
        }
        $group = $map.$groupk
        foreach($projk in get-propertynames $group) {
            $proj = $group.$projk
            if ($proj.profiles -ne $null) {
                foreach($profk in get-propertynames $proj.profiles) {
         
                    if ($proj.profiles.$profk -is [System.Collections.IDictionary]) {
                        # set full path as if profiles were created at project level
                        $null = add-property $proj.profiles.$profk -name _fullpath -value "$groupk.$projk.$profk" -overwrite
                         #use fullpath for backward compatibility       
                        $null = add-property $proj.profiles.$profk -name fullpath -value $proj.profiles.$profk._fullpath -overwrite
                    } else {
                        #remove every property that isn't a real profile
                        $proj.profiles.Remove($profk)
                    }
                }
                # expose profiles at project level
                $null = add-properties $proj $proj.profiles -merge -ifNotExists
            }
            # use fullpath for backward compatibility
            if ($proj._fullpath) {
                $null = add-property $proj -name fullpath -value $proj._fullpath -overwrite
            }
        }

        # use fullpath for backward compatibility
        if ($group._fullpath) {
            $null = add-property $group -name fullpath -value $group._fullpath -overwrite
        }
        
    }
    return $pmap
}

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

function __import-mapproject($proj) {
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


function __import-mapprofile($prof, $parent) {
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
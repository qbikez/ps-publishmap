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

function import-singlemapfile($file) {
    $fullname = $file
    if ($fullname.FullName -ne $null) { $Fullname =$Fullname.FullName }
    $map = & "$FullName"
    
    #$publishmap_obj = ConvertTo-Object $publishmap
    $pmap = import-mapobject $map

   return $pmap
}

function import-mapobject($map) {
    $pmap = @{}
   # foreach($a in $publishmap) {
        foreach($groupk in $map.keys) {
            # group = ne, legimi, hds, etc
            #$group = $a[$groupk]
            $r = import-mapgroup $map $groupk
            $pmap += $r
        }
   # }
   
   return $pmap
}

function import-mapgroup($publishmap, $groupk) {
    Write-Verbose "processing map $groupk"
    $settings = $publishmap.$groupk.settings
    $globalProffiles = $publishmap.$groupk.global_profiles
    $keys = get-propertynames $publishmap.$groupk
    add-property $publishmap.$groupk "level" 1
    add-property $publishmap.$groupk -name fullpath  -value "$groupk"
    foreach($projk in $keys) {
            #do not process special global settings
            if ($projk -in "settings","global_profiles") {
                continue
            }
            #proj = viewer,website,drmserver,vfs, etc.
            #$proj = $group[$projk]
                   $proj = $publishmap.$groupk.$projk
     if ($settings -ne $null) {
                 add-property $proj "settings" $settings
                 #$proj | add-member -name settings -membertype noteproperty -value $settings
            }

            add-property $proj "level" 2
            add-property $proj -name fullpath  -value "$groupk.$projk"
            
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
                # make sure all profiles exist
                check-profileName $proj $profk
                $prof = $proj.profiles.$profk
                
                #inherit settings from project
                inherit-properties -from $proj -to $prof -exclude (@("profiles") + $profiles + @("level","fullpath"))
                
                
                #inherit global profile settings
                if ($globalProffiles -ne $null -and $globalProffiles.$profk -ne $null -and $prof.inherit -ne $false -and $proj.inherit -ne $false) {
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
                add-property $prof "level" 3

                #fill meta properties
                add-property $prof -name project -value $proj
                add-property $prof -name fullpath  -value "$groupk.$projk.$profk"
                add-property $prof -name name -value "$profk" -ifnotexists               
                
                add-property $publishmap.$groupk.$projk -name $profk -value $prof              
            }
        }

    return $publishmap
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
                            add-property $proj -name "profiles" -value @{}
                        }
                        add-property $proj.profiles -name $profk -value $prof
                    }
                    else {
                        continue
                    }
                }
}
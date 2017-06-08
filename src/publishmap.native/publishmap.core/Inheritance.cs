using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Publishmap.Utils.Inheritance
{
    public static class Inheritance
    {
        public static void Init()
        {
            // force linq loading
            new Dictionary<string, string>().Any();
            new Hashtable();
        }
        public static void AddProperties(
            IDictionary obj,
            IDictionary props,
            bool ifNotExists = false,
            bool merge = false,
            IEnumerable<object> exclude = null
            )
        {
            foreach (var key in props.Keys)
            {
                var val = props[key];
                if (exclude?.Contains(key) ?? false) continue;

                try
                {
                    AddProperty(obj, name: (string)key, value: val, ifNotExists: ifNotExists, merge: merge);
                }
                catch (Exception ex)
                {
                    throw new Exception($"failed to add property '{key}' with value '{val}': {ex.Message}");
                }
            }
        }
        public static void AddProperty(
            IDictionary obj,
            string name,
            object value,
            bool ifNotExists = false,
            bool overwrite = false,
            bool merge = false)
        {
            if (obj.Contains(name))
            {
                if (merge && obj[name] is IDictionary && value is IDictionary)
                {
                    AddProperties((IDictionary)obj[name], (IDictionary)value, ifNotExists: ifNotExists, merge: merge);
                    // $r = add-properties $object.$name $value -ifNotExists:$ifNotExists -merge:$merge 
                    // return $object
                }
                else if (ifNotExists)
                {
                    return;
                }
                else if (overwrite)
                {
                    obj[name] = value;
                }
                else
                {
                    throw new ArgumentException($"property '{name}' already exists with value '{obj[name]}'");
                }
            }
            else
            {
                if (obj is IDictionary)
                {
                    obj[name] = value;
                }
                else
                {
                    throw new NotSupportedException("optimization - only support hashtabes");
                }
            }
        }

        public static void AddMetaProperties(
            IDictionary group, string fullpath, IEnumerable<object> specialKeys)
        {

            var splits = fullpath.Split('.');
            var level = splits.Length - 1;

            AddProperty(group, "_level", level);
            AddProperty(group, "_fullpath", fullpath.Trim('.'));
            if (splits.Length > 0)
            {
                AddProperty(group, "_name", splits[splits.Length - 1]);
            }

            var keys = group.Keys;

            foreach (var projk in keys)
            {
                //do not process special global settings
                if (specialKeys.Contains(projk))
                {
                    continue;
                }
                var path = $"{fullpath}.{projk}";
                if (group[projk] is IDictionary)
                {
                    AddMetaProperties((IDictionary)group[projk], path, specialKeys);
                }
            }


        }

        public static IDictionary CopyHashtable(IDictionary org)
        {
            var result = new Hashtable();
            foreach (var key in org.Keys)
            {
                if (org[key] is IDictionary)
                {
                    result[key] = CopyHashtable((IDictionary)org[key]);
                }
                else
                {
                    result[key] = org[key];
                }
            }
            return result;
        }

        public static void AddInheritedProperties(
            IDictionary from,
            IDictionary to,
            IEnumerable<object> exclude = null,
            bool valuesOnly = false
        )
        {
            if (exclude == null) exclude = new string[] { };

            var toProcess = new Dictionary<string, object>();
            foreach (string key in from.Keys)
            {
                var value = from[key];
                var shouldExclude = false;
                if (exclude.Contains(key)) shouldExclude = true;
                if (exclude.Any(e => Regex.IsMatch(key, $"^{e}$"))) shouldExclude = true;

                if (value is System.Collections.IDictionary)
                {
                    if (valuesOnly)
                    {
                        shouldExclude = true;
                    }
                    else
                    {
                        var newvalue = CopyHashtable((IDictionary)value);
                        value = newvalue;
                    }
                }
                if (!shouldExclude)
                {
                    toProcess[key] = value;
                }
            }

            if (toProcess.Any())
            {
                try
                {
                    AddProperties(to, toProcess, merge: true, ifNotExists: true);
                }
                catch (Exception ex)
                {
                    throw new Exception($@"failed to inherit properties:{ex.Message}
                        from:
                        {from}
                        to:
                        {to}");
                }
            }


            /* 
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
                  }
              }
                         */
        }

        private static string GetInheritedProfileName(IDictionary prof) {
            return (string)prof["_inherit_from"];
        }

        private static bool AlreadyInherits(IDictionary prof) {
            return prof.Contains("_inherited_from");
        }

        public static void PostProcessPublishmap(IDictionary map)
        {
            var groupsToRemove = new List<string>();
            foreach (string groupk in map.Keys)
            {
                // remove generated properties from top-level
                if (groupk.StartsWith("_"))
                {
                    groupsToRemove.Add(groupk);
                    continue;
                }
                var group = (IDictionary)map[groupk];

                foreach (string projk in group.Keys)
                {
                    if (!(group[projk] is IDictionary)) continue;
                    var proj = (IDictionary)group[projk];
                    if (proj.Contains("profiles"))
                    {
                        var profiles = ((IDictionary)proj["profiles"]);
                        var profilesToRemove = new List<string>();
                        foreach (string profk in profiles.Keys)
                        {
                            var profitem = profiles[profk];

                            if (!(profitem is IDictionary))
                            {
                                // write-verbose "removing non-profile property '$groupk.$projk.$profk'"
                                // remove every property that isn't a real profile
                                profilesToRemove.Add(profk);
                                continue;
                            }
                            else
                            {
                                //   write - verbose "adding post-properties to '$groupk.$projk.$profk'"
                                // set full path as if profiles were created at project level
                                var prof = (IDictionary)profitem;
                                AddProperty(prof, "_fullpath", $"{groupk}.{projk}.{profk}", overwrite: true);
                                AddProperty(prof, "_name", profk, overwrite: true);
                                //  use fullpath for backward compatibility    
                                AddProperty(prof, "fullpath", $"{groupk}.{projk}.{profk}", overwrite: true);
                                AddProperty(prof, "project", proj, overwrite: true);
                            }
                        }
                        foreach (var k in profilesToRemove) profiles.Remove(k);
                        // # expose profiles at project level
                        AddProperties(proj, profiles, merge: true, ifNotExists: true);

                    }
                    //  use fullpath for backward compatibility
                    if (proj.Contains("_fullpath"))
                    {
                        AddProperty(proj, "fullpath", proj["_fullpath"], overwrite: true);
                    }
                }

                //# use fullpath for backward compatibility
                if (group.Contains("_fullpath"))
                {
                    AddProperty(group, "fullpath", group["_fullpath"], overwrite: true);
                }
            }

            foreach (var k in groupsToRemove) map.Remove(k);
        }

        private static void ProcessInheritanceChain(IDictionary prof, IDictionary profiles)
        {
            var inheritFrom = GetInheritedProfileName(prof);
            if (inheritFrom != null)
            {
                if (!profiles.Contains(inheritFrom))
                {
                    // write - warning "cannot find inheritance base '$($prof._inherit_from)' for profile '$($prof._fullpath)'"
                }
                else
                {
                    var cur = prof;
                    var hierarchy = new List<IDictionary>();
                    while ((inheritFrom = GetInheritedProfileName(cur)) != null && !AlreadyInherits(prof))
                    {
                        hierarchy.Add(cur);
                        var baseprof = (IDictionary)profiles[inheritFrom];
                        cur = baseprof;
                    }
                    for (var i = hierarchy.Count - 1; i >= 0; i--)
                    {
                        cur = hierarchy[i];
                        if (!AlreadyInherits(cur)) {
                            inheritFrom = GetInheritedProfileName(cur);
                            var baseprof = (IDictionary)profiles[inheritFrom];
                            // write-verbose "inheriting properties from '$($cur._inherit_from)' to '$($cur._fullpath)'"
                            AddInheritedProperties(baseprof, cur, valuesOnly: true, exclude: new[] { "_inherit_from", "_inherited_from" });
                            AddProperty(cur, "_inherited_from",inheritFrom);
                        }
                    }
                }
            }
        }

        /*
            $proj = $group.$projk
            if ($null -ne $proj.profiles) {
                foreach($profk in get-propertynames $proj.profiles) {
                    $prof = $proj.profiles.$profk
                    if ($prof -is [System.Collections.IDictionary]) {
                        write-verbose "adding post-properties to '$groupk.$projk.$profk'" 
                        # set full path as if profiles were created at project level
                        $null = add-property $prof -name _fullpath -value "$groupk.$projk.$profk" -overwrite
                        $null = add-property $prof -name _name -value "$profk" -overwrite
                        # use fullpath for backward compatibility    
                        if ($prof._fullpath -eq $null) {
                            write-warning "no fullpath property!"
                        }   
                        $null = add-property $prof -name fullpath -value $prof._fullpath -overwrite
                        # expose project at profile level
                        $null = add-property $prof -name project -value $proj
                    } else {
                        #write-verbose "removing non-profile property '$groupk.$projk.$profk'"
                        #remove every property that isn't a real profile
                        $proj.profiles.Remove($profk)
                    }
                    if ($null -ne $prof._inherit_from) {
                        if ($proj.profiles.$($null -eq $prof._inherit_from)) {
                            write-warning "cannot find inheritance base '$($prof._inherit_from)' for profile '$($prof._fullpath)'"
                        } else { 
                            $cur = $prof
                            $hierarchy = @()
                            while($null -ne $cur._inherit_from -and $null -eq $cur._inherited_from) {                                
                                $hierarchy += $cur
                                $base = $proj.profiles.$($cur._inherit_from)
                                $cur = $base
                            }
                            for($i = ($hierarchy.length - 1); $i -ge 0; $i--) {
                                $cur = @($hierarchy)[$i]
                                $base = $proj.profiles.$($cur._inherit_from)
                               # write-verbose "inheriting properties from '$($cur._inherit_from)' to '$($cur._fullpath)'"
                                inherit-properties -from $base -to $cur -valuesonly -exclude @("_inherit_from","_inherited_from")
                                $null = add-property $cur -name _inherited_from  -value $($cur._inherit_from)
                            }                            
                        }
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
    }
    */

        public static void AddGlobalSettings(IDictionary proj, IDictionary settings)
        {
            if (null != settings)
            {
                //write-verbose "inheriting global settings to $($proj._fullpath). strip=$stripsettingswrapper"
                if (settings.Contains("_strip"))
                {
                    var stripsettingswrapper = settings["_strip"];
                    AddInheritedProperties(settings, proj, /*ifNotExist: true, merge:true,*/ exclude: new[] { "_strip" });
                }
                else
                {
                    AddProperty(proj, "settings", settings, ifNotExists: true, merge: true);
                }
            }

        }

        /* 
        function Add-GlobalSettings($proj, $settings) {
            Measure-function  "$($MyInvocation.MyCommand.Name)" {

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
            }
            */

        public static IDictionary ImportGenericGroup(IDictionary group,
            string fullpath,
            IDictionary settings = null,
            string settingskey = "settings",
            IEnumerable<object> specialkeys = null
        )
        {
            if (specialkeys == null)
            {
                specialkeys = new[] { "settings", "global_profiles" };
            }

            //  Write-Verbose "processing map path $fullpath"

            var result = new Hashtable();

            //# only direct children inherit settings
            var onelevelsettingsinheritance = true;
            IDictionary childsettings = null;
            //#get settings for children
            if (group.Contains(settingskey))
            {
                childsettings = (IDictionary)group[settingskey];
            }
            else
            {
                if (!onelevelsettingsinheritance)
                {
                    childsettings = settings;
                }
            }

            object[] keys = new object[group.Keys.Count];
            group.Keys.CopyTo(keys, 0);
            foreach (string projk in keys)
            {
                //#do not process special global settings
                if (specialkeys.Contains(projk))
                {
                    continue;
                }
                var subgroup = group[projk];
                if (!(subgroup is System.Collections.IDictionary))
                {
                    continue;
                }
                var path = $"{fullpath}.{projk}";

                ProcessInheritanceChain((IDictionary)subgroup, group);
                AddInheritedProperties(group, (IDictionary)subgroup, valuesOnly: true);
                // # this should be run only once per group, right? 
                // # why is this needed here?
                if (null != settings)
                {
                    AddGlobalSettings(group, settings);
                }
                var r = ImportGenericGroup((IDictionary)subgroup, path, childsettings, settingskey, specialkeys);

                //result.Add("" r);
            }

            if (null != settings)
            {
                AddGlobalSettings(group, settings);
            }

            return group;
        }

        /*
    if ($null -ne $settings) {
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
} */

    }

}

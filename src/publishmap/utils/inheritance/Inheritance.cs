using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;

namespace Publishmap.Utils.Inheritance
{
    public static class Inheritance
    {
        public static void Init()
        {
            // force linq loading
            new Dictionary<string, string>().Any();
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
        /*
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

*/
    }
}
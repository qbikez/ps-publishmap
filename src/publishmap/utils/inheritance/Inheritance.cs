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

    }
}
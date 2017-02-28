using System;
using System.Collections;
using System.Collections.Generic;

namespace Publishmap.Utils.Inheritance
{
    public static class Inheritance
    {
        public static void AddProperty(
            IDictionary obj,
            string name,
            object value,
            bool ifNotExusts = false,
            bool overwrite = false,
            bool merge = false)
            {
                if (obj.Contains(name)) {
                    if (merge && obj[name] is IDictionary && value is IDictionary) {
                        throw new NotSupportedException("merging is nott supported yet");
                        // $r = add-properties $object.$name $value -ifNotExists:$ifNotExists -merge:$merge 
                        // return $object
                    }
                    else if (ifNotExusts) {
                        return;
                    }
                    else if (overwrite) {
                        obj[name] = value;
                    }
                    else {
                        throw new ArgumentException($"property '{name}' already exists with value '{obj[name]}'");
                    }
                }
                if (obj is IDictionary) {
                    obj[name] = value;
                } else {
                    throw  new NotSupportedException("optimization - only support hashtabes");
                }
            }
    }
}
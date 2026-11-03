using System.Collections;
using System.Management.Automation;

namespace Publishmap.Powershell
{
    [Cmdlet(VerbsCommon.Add, "Property")]
    public class AddPropertyCmdlet : Cmdlet
    {
        [Parameter(ValueFromPipeline = true, Position = 1)]
        public IDictionary Object { get; set; }

        [Parameter(Mandatory=true, Position=2)]
        public string Name { get; set; }
        
        [Parameter(Mandatory=true, Position=3)]
        public object Value { get; set; }

        [Parameter()]
        public bool IfNotExists {get;set;}
        [Parameter()]
        public bool Overwrite {get;set;}
        [Parameter()]
        public bool Merge {get;set;}
        protected override void ProcessRecord()
        {
            Publishmap.Utils.Inheritance.Inheritance.AddProperty(Object, Name, Value, IfNotExists, Overwrite, Merge);
        }
    }  

    
}
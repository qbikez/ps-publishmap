$helpersPath = (Split-Path -parent $MyInvocation.MyCommand.Definition);

. "$helpersPath\imports.ps1"


function loadLib($lib) {
    $libdir = split-path -parent $lib 

    $OnAssemblyResolve = [System.ResolveEventHandler] {
        param($sender, $e)

        foreach($a in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
            if ($a.FullName -eq $e.Name) {
                return $a
            }
            $splits = $e.Name.Split(",")
            if ($a.GetName().Name -eq $splits[0]) {
                return $a
            }
        }
        Write-Warning "failed to resolve assembly '$($e.name)'"
        return $null
    }


    foreach($asm in (get-childitem $libdir -Filter "*.dll")) {
        try {
            [System.Reflection.Assembly]::LoadFile($asm.fullname)
            write-host "imported $($asm.Name)"
        } catch {
            write-warning "failed to import $($asm.Name): $($_.Exception.Message)"
        }
    }
    
    try {
       
  
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($OnAssemblyResolve)
        Add-Type -Path "$libdir\inheritance.dll"

    } catch {
        throw $_
    }
    finally {
        [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($OnAssemblyResolve)

    }
}


$lib = "$helpersPath\utils\inheritance\bin\Debug\netcoreapp1.1\win10-x64\publish\inheritance.dll"
loadlib $lib


function add-property {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Position=1)] $object, 
        [Parameter(Mandatory=$true,Position=2)] $name, 
        [Parameter(Mandatory=$true,Position=3)] $value, 
        [switch][bool] $ifNotExists,
        [switch][bool] $overwrite,
        [switch][bool] $merge
    )  
        [Publishmap.Utils.Inheritance.Inheritance]::AddProperty($object, $name, $value, $ifNotExists, $overwrite, $merge)
    }

Export-ModuleMember -Function `
        Get-Entry, Import-Map, `
        Import-PublishMap, Get-Profile, `
        Get-PropertyNames, Add-Property, Add-Properties, `
        Convert-Vars, ConvertTo-Hashtable, ConvertTo-Object, `
	Convert-PropertiesFromVars, `
        Add-InheritedProperties, `
        Measure-Function `
    -Alias *
    
    

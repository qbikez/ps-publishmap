$helpersPath = (Split-Path -parent $MyInvocation.MyCommand.Definition);

. "$helpersPath\imports.ps1"

Export-ModuleMember -Function `
        Get-Entry, Import-Map, `
        Import-PublishMap, Get-Profile, `
        Get-PropertyNames, Add-Property, Add-Properties, `
        Convert-Vars, ConvertTo-Hashtable, ConvertTo-Object, `
	replace-properties, `
        inherit-properties `
    -Alias *
    
    

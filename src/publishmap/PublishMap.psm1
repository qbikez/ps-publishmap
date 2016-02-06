$helpersPath = (Split-Path -parent $MyInvocation.MyCommand.Definition);

# grab functions from files
Resolve-Path $helpersPath\functions\*.ps1 | 
    ? { -not ($_.ProviderPath.Contains(".Tests.")) } |
    % { . $_.ProviderPath }


Export-ModuleMember -Function `
    Import-MapFile, Import-MapObject, `
    Get-Profile, `
    Get-Entry

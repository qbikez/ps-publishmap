# grab functions from files
Resolve-Path $psscriptroot\functions\*.ps1 | 
    ? { -not ($_.ProviderPath.Contains(".Tests.")) } |
    ? { -not ((split-path -leaf $_).StartsWith("_")) } |
    % { . $_.ProviderPath }


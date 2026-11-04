$targets = @{}
foreach ($partial in @(
        . "$psscriptroot/test.targets.ps1"
    )) {
    foreach ($key in $partial.Keys) {
        $targets[$key] = $partial[$key]
    } 
}

return $targets
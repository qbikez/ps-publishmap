$root = $PSScriptRoot
if (!$root) { $root = "." }

req powershell-yaml
$installConfig = get-content $root/install.yaml | ConvertFrom-Yaml -ordered
$dependencies = $installConfig.dependencies

. "$PSScriptRoot/helpers.ps1"

$parsed = @{}

foreach ($kvp in $dependencies.GetEnumerator()) {
    $group = $kvp.key
    $list = $dependencies["$group"]

    $submodules = @{}
    
    foreach ($item in $list) {
        $package = parse-packageEntry $item
        $package.exec = {
            param($_context)
            install-mypackage $_context.self
        }
        $submodules[$package.name] = $package
    }
    $parsed.$group = $submodules

    $parsed.$group.list = {
        return $submodules
    }.GetNewClosure()

    $parsed.$group.exec = {
        param($_context)
        install-mygroup $_context.self
    }

}

return $parsed
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
            param($ctx)
            install-mypackage $ctx.self
        }
        $submodules[$package.name] = $package
    }
    $parsed.$group = $submodules

    $parsed.$group.list = {
        return $submodules
    }.GetNewClosure()

    $parsed.$group.exec = {
        param($context)
        install-mygroup $context.self
    }

}

return $parsed
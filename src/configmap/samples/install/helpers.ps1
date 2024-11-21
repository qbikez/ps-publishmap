function parse-packageEntry($entry) {
    if ($entry.GetType().Name -eq "String") {
        if ($entry -notmatch "^\s*(?<name>.*?)\s*(@(?<version>[a-zA-Z0-9\.]+)){0,1}(\[(?<installer>.+)\]){0,1}\s*$") {
            throw "unrecognized package entry '$entry'"
        }

        $packageName = $matches["name"]
        $installer = $matches["installer"]
        $version = $matches["version"]
    }
    elseif ($entry.GetType().Name -eq "OrderedDictionary") {
        $packageConfig = $entry
        $packageName = $entry["name"]
        $after = $packageConfig["after"]
        $version = $packageConfig["version"]
    }
    else {
        throw "unrecognized entry type $($entry.GetType().Name)"
    }


    $defaultInstaller = "choco"
    $additionalArgs = ""
    
    if (!$installer) {
        $installer = $defaultInstaller
    }
    elseif ($installer.StartsWith("-")) {
        $installer = $defaultInstaller
        $additionalArgs = $matches["installer"]
    }
    
    $defaultArgs = switch ($installer) {
        "choco" {
            $a = "install -y $packageName"
            if ($version) {
                $a += " -v $version"
            }
            $a
        }
    }
    
    $installerArgs = "$defaultArgs"
    if ($additionalArgs) {
        $installerArgs = "$installerArgs $additionalArgs"
    }

    if ($installer -match "(?<installer>[^\s]+)\s+(?<args>.+)") {
        $installerArgs = $matches["args"]
        $installer = $matches["installer"]
    }
    else {
        
    }

    $installerArgs = $installerArgs.split(" ") # let's hope there are no quoted arguments...
    
    return @{
        name          = $packageName
        installer     = $installer
        installerArgs = $installerArgs
        after = $after
    }
}

function install-mygroup($group) {
    $submodules = get-completionlist $group

    write-verbose "installing group: $($submodules.Keys)" -verbose
    foreach($kvp in $submodules.GetEnumerator()) {
        write-verbose "installing '$($kvp.key)'"
        if (!$kvp.value.installer) {
            throw "package '$($kvp.key)' doesn't have an installer"
        }
        Install-mypackage $kvp.value
    }
}
function install-mypackage($package) {
    write-verbose "$($package.installer) $($package.installerArgs)"
    if (!$package.installer) {
        throw "package '$($package.name)' doesn't have an installer"
    }
    & $package.installer $package.installerArgs
    if ($lastexitcode -eq 0 -and $package.after) {
        Write-Verbose "executing after script"
        Invoke-Expression -Command $package.after
    }
}

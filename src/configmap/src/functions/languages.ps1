#requires -version 7.0

$script:languages = @{
    "build" = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "_sourceFile", "_settings", "_dependsOn", "_internal", "description", "validate", "get", "set", "type", "file")
    }
    "conf"  = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "_sourceFile", "_settings", "_dependsOn", "_internal", "description", "validate", "get", "set", "type", "file")
    }
}

function Get-MapLanguage {
    param([ValidateSet("build", "conf")]$language)
    return $script:languages.$language
}

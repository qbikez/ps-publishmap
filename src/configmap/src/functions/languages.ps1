#requires -version 7.0

$script:languages = @{
    "build" = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "_sourceFile", "_settings", "_dependsOn", "description", "validate", "get", "set", "process")
    }
    "conf"  = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "_sourceFile", "_settings", "_dependsOn", "description", "validate", "get", "set", "process")
    }
}

function Get-MapLanguage {
    param([ValidateSet("build", "conf")]$language)
    return $script:languages.$language
}

#requires -version 7.0

$script:languages = @{
    "build" = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "_settings")
    }
    "conf"  = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "_settings", "get", "set", "validate")
    }
}

function Get-MapLanguage {
    param([ValidateSet("build", "conf")]$language)
    return $script:languages.$language
}

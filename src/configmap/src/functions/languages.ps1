#requires -version 7.0

$script:languages = @{
    "build" = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir")
    }
    "conf"  = @{
        reservedKeys = @("exec", "list", "options", "#include", "_baseDir", "get", "set", "validate")
    }
}

function Get-MapLanguage {
    param([ValidateSet("build", "conf")]$language)
    return $script:languages.$language
}

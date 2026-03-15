$targets = @{
    "build" = {
        param($ctx, [bool][switch]$noRestore)

        $a = @()
        if ($noRestore) {
            $a += "--no-restore"
        }
        dotnet build @a
    }
    # NPM_SCRIPTS_PLACEHOLDER
}

return $targets
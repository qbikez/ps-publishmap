[ordered]@{
    "build" = {
        param([bool][switch]$noRestore)

        $a = @()
        if ($noRestore) {
            $a += "--no-restore"
        }
        dotnet build @a
    }
}

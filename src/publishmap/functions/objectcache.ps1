
function set-cachedobject($triggerfile, $object) {
    if (!(test-path $triggerfile)) { throw "trigger file '$triggerfile' not found" }
    $f = gi $triggerfile
    $ts = $f.LastWriteTimeUtc
    $global:cache[$triggerfile] = @{
        ts = $ts
        value = $object
        file = (gi $triggerfile).FullName
    }
}
function get-cachedobject($triggerfile) {
    if (!(test-path $triggerfile)) { throw "trigger file '$triggerfile' not found" }
    if ($global:cache[$triggerfile] -ne $null) {
        $f = gi $triggerfile
        $ts = $f.LastWriteTimeUtc
        if ($ts -le $global:cache[$triggerfile].ts)  {
            return $global:cache[$triggerfile]
        }
    }
    return $null
}
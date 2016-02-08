
function add-cachedobject($triggerfile, $object) {
    $f = gi $triggerfile
    $ts = $i.LastWriteTimeUtc
    $global:cache[$triggerfile] = @{
        ts = $ts
        value = $object
        $file = (gi $triggerfile).FullName
    }
}
function get-cachedobject($triggerfile) {
    if ($global:cache[$triggerfile] -ne $null) {
        $f = gi $triggerfile
        $ts = $i.LastWriteTimeUtc
        if ($ts -le $global:cache[$triggerfile].ts)  {
            return $global:cache[$triggerfile]
        }
    }
    return $null
}
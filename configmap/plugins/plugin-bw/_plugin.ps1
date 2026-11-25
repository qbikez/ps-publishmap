# Bitwarden `bw:{item}[/{field}]` option values. The implementation (bw.ps1) is loaded
# lazily, the first time a `bw:` value is resolved.
@{
    name           = 'bw'
    description    = 'Resolve bw:{item}[/{field}] option values from Bitwarden'
    implementation = 'bw.ps1'

    valuePrefixes  = @{
        'bw:' = @{
            secret  = $true
            resolve = {
                param($Reference)
                $splits = $Reference -split '/', 2
                get-bwSecret $splits[0] $splits[1]
            }
        }
    }
}

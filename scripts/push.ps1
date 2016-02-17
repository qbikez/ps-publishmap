[CmdletBinding(SupportsShouldProcess=$true)]
param([switch][bool]$newversion)


function push-module {
[CmdletBinding(SupportsShouldProcess=$true)]
param($modulepath, [switch][bool]$newversion)

    $envscript = "$psscriptroot\..\.env.ps1" 
    if (test-path "$envscript") {
        . $envscript
    }

    $repo = "$env:PS_PUBLISH_REPO"
    $key = "$env:PS_PUBLISH_REPO_KEY"

    . $psscriptroot\imports\set-moduleversion.ps1
    . $psscriptroot\imports\nuspec-tools.ps1

    $ver = get-moduleversion $modulepath
    if ($newversion) {
        $newver = Incremet-Version $ver
    } else {
        $newver = $ver
    }
    set-moduleversion $modulepath -version $newver


    Publish-Module -Path $modulepath -Repository $repo -Verbose -NuGetApiKey $key

}

$root = $psscriptroot
$modules = get-childitem "$root\..\src" -filter "*.psm1" -recurse | % { $_.Directory.FullName }
$modules | % { push-module $_ -newversion:$newversion }

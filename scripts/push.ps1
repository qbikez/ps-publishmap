[CmdletBinding(SupportsShouldProcess=$true)]
param([switch][bool]$newversion)

$envscript = "$psscriptroot\..\.env.ps1" 
if (test-path "$envscript") {
    . $envscript
}

rmo powershellget; ipmo powershellget;

$repo = "$env:PS_PUBLISH_REPO"
$key = "$env:PS_PUBLISH_REPO_KEY"

. $psscriptroot\imports\set-moduleversion.ps1
. $psscriptroot\imports\nuspec-tools.ps1

$modulepath = "$psscriptroot\..\src\publishmap"

if ($newversion) {
    $ver = get-moduleversion $modulepath
    $newver = Incremet-Version $ver
    set-moduleversion $modulepath -version $newver
}

Publish-Module -Path $modulepath -Repository $repo -Verbose -NuGetApiKey $key


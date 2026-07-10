#requires -version 7.0

# this is for piping utf-8 output to out-host (used when invoking concurretly). 
# Otherwise, the UTF-8 characters will be garbled in the console.
[System.Console]::OutputEncoding = $OutputEncoding

$helpersPath = (Split-Path -Parent $MyInvocation.MyCommand.Definition)

# Import all function files in dependency order
. "$helpersPath\functions\plugins.ps1"
. "$helpersPath\functions\languages.ps1"
. "$helpersPath\functions\resolve-map.ps1"
. "$helpersPath\functions\completion.ps1"
. "$helpersPath\functions\map-entries.ps1"
. "$helpersPath\functions\invoke-entry.ps1"
. "$helpersPath\functions\help.ps1"
. "$helpersPath\functions\initialize.ps1"
. "$helpersPath\functions\qbuild.ps1"
. "$helpersPath\functions\qconf.ps1"

. "$helpersPath\functions\plugins-init.ps1" -PluginsPath "$helpersPath\plugins"

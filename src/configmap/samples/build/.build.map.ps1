$targets = @{
    "build" = {
        param($ctx, [bool][switch]$noRestor)

        invoke-build $args
    }
}

function invoke-build($args) {
    write-host "build $args"
}

function get-script-args($func) {
    # todo: convert AST parameters to DynamicParam
    $parameters = $func.AST.ParamBlock.Parameters
}

return $targets
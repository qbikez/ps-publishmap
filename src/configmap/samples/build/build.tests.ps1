BeforeAll {
    $targets = @{
        "build" = {
            param($ctx, [bool][switch]$noRestor)

            invoke-build $args
        }
    }

}

Describe "script exposes custom parameters" {
    It "should return parameters" {
    
        $parameters = get-script-args $func
        
    }
}

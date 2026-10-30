# Built-in get/set implementations for Entry._template types.
return [ordered]@{
    appconfig = @{
        get = {
            param($ctx, $options, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'appconfig'
            Find-ActiveOption -file $file -options $options
        }
        set = {
            param($ctx, $key, $value, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'appconfig'
            Set-AppConfigOption -File $file -Values $value
        }
    }
    dotenv    = @{
        get = {
            param($ctx, $options, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'dotenv'
            Find-ActiveEnvOption -File $file -Options $options
        }
        set = {
            param($ctx, $key, $value, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'dotenv'
            Set-DotEnvOption -File $file -Values $value
        }
    }
}

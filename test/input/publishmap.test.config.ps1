param([switch][bool] $silent)

$publishmap = @{
   
    test = [ordered]@{
        settings = @{
            siteAuth = @{
                    username = "user"
                    password = "pass"
            }
        }
        global_profiles =@{
            dev = @{
                    connectionStringName = "dfdfs"
                    db_legimi = @{ connectionStringName = "UsersDb-dev" }
                    Config = "Debug"
                    Password = "?"
                    profile = "ne-dev.pubxml"
                    Machine = "machine"
                }
            dev_copy = @{
                _inherit_from = "dev"
            }
            dev_2 = @{
                _inherit_from = "dev"
            }
            qa = @{
                Config = "qa"
            }
        }
        use_default_profiles = @{
            sln = "Platform\sln\NowaEra\NowaEra.Server.Content.sln"        
            proj = "Platform\src\server\NowaEra.Server.Content\NowaEra.Server.Content.csproj"
            task = "Migrate"            
            #deployprop="DeployBookMeta"
            appname="svc/content"           
        }
        db_1 = @{
        }
        additional = @{
            profiles = @{
                dev = @{
                    password = "overriden"
                }
                prod = @{
                    name = "prod"
                }
            }
        }
        override_default_profiles = @{
            task = "Migrate"
            appname = "override"
            profiles = @{
                dev = @{
                    appname = "override/dev"
                    password = "overriden"
                    new_prop = "abc"
                }
                dev_copy = @{
                    Config = "copy"
                }
                dev_3 = @{
                    _inherit_from = "dev"
                    profile = "ne-dev-3.pubxml"
                    task = "Migrate-3"
                }
            }
        }
        do_not_inherit_global = @{
            inherit = $false
            profiles = @{
                dev = @{
                    new_prop = "abc"
                }
            }
        }
        do_not_inherit_local = @{
            profiles = @{
                dev = @{
                    inherit = $false
                    new_prop = "abc"
                }
            }
        }
        generic = @{
            profiles = @{
                prod_N_ = @{ 
                    computername = "prod{N}.cloudapp.net"; 
                    Port = "1{N}80"
                }
                
            }
        }

    }
    
}

return $publishmap
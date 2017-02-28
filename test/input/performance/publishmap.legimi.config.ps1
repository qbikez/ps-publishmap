$publishmap = @{
    legimi = @{
        global_profiles = @{
            default = @{
                    Config = "Debug"
            }
            dev = @{
                    Config = "Devel"
                    ComputerName = "phobos"                    
                    Machine = "phobos:8172"
                    Password = "?"
                    BaseAppPath = "legimi-dev"
                    BaseDir = "c:\www\legimi-dev"
            }
            alpha_intl = @{
                    _inherit_from = "dev"
                    baseapppath = "legimi-alpha-intl"
                    BaseDir = "c:\www\legimi-alpha-intl"
            }
            beta_intl = @{
                    _inherit_from = "dev"
                    baseapppath = "legimi-beta-intl"
                    BaseDir = "c:\www\legimi-beta-intl"                    
            }
            alpha_pl = @{
                    _inherit_from = "dev"
                    Config = "Devel"
                    ComputerName = "phobos"                    
                    Machine = "phobos:8172"
                    Password = "?"
                    BaseAppPath = "legimi-alpha"
                    BaseDir = "c:\www\legimi-alpha"
                    BaseUrl = "http://alpha.legimi.pl"
            }
            beta_pl = @{
                    _inherit_from = "dev"
                    Config = "Devel"
                    ComputerName = "phobos"                    
                    Machine = "phobos:8172"
                    Password = "?"
                    BaseAppPath = "legimi-beta"
                    BaseDir = "c:\www\legimi-beta"
                    BaseUrl = "http://beta.legimi.pl"
            }
            alpha_de = @{
                _inherit_from = "dev"
                ComputerName = "valkyria"
                Machine = "valkyria:8172"
                BaseAppPath = "legimi-alpha-de"
                profile = "legimi-alpha-de.pubxml"
                Config = "Devel"
                BaseUrl = "http://alpha.legimi.de"
                BaseDir = "c:\www\legimi-alpha-de"
            }
            prod_de = @{
                Config = "Release"
                ComputerName = "legimi-de.cloudapp.net"
                Machine = "legimi-de.cloudapp.net:8172"
                BaseAppPath = "legimi-prod"
                BaseDir = "c:\www\legimi-prod"
                profile = "legimi-de-prod.pubxml"
                BaseUrl = "http://legimi-de.cloudapp.net"
            }
            prod_pl = @{
                    Config = "Release"
                    ComputerName = "pegaz"                    
                    Password = "?"
                    profile = "legimi-prod.pubxml"
                    Machine = "pegaz.legimi.com:8172"
                    BaseAppPath = "legimi-azure"
                    BaseDir = "c:\www\legimi-azure-www"
                    BaseUrl = "http://www.legimi.pl"                    
            }      
            alpha_cn = @{
                    _inherit_from = "dev"
                    Config = "Devel"
                    ComputerName = "phobos"                    
                    Machine = "phobos:8172"
                    BaseAppPath = "legimi-alpha-cn"
                    BaseDir = "c:\www\legimi-alpha-cn"
                    BaseUrl = "http://phobos.legimi.com:11080"
            }           
        }
        site = @{            
            group = @("www", "payments", "download_svc", "workflow", "dao")
        }
		audio = @{
			group = @("audio_encryptor", "audio_zipper", "foreign_words", "audio_generator", "audio_recognizer", "audio_matcher", "audio_wm")
		}
		audio_main_srv = @{
			# everything from audio group which goes to main polish server
			#audio generator and recognizer tasks are deployed to other servers,
			#due to OS compatibility issues
			group = @("audio_encryptor", "audio_zipper", "foreign_words", "audio_matcher", "audio_wm")
		}
		importers = @{
			group = @("import_virtualo", "import_pdw", "import_olesiejuk", "import_soniadraga")
		}
		publishapi_all = @{
			# everything from repo legimi.ext.services
			group = @("task_mobi_generator", "task_imageproc", "task_deduplicator", "publishapi")
		}
		core = @{
            # everything from repo legimi.core
			group = @("event_processor", "dao", "task_content_importer", "workflow")
		}
		libreka = @{
			group = @("unl_chunks_report", "libreka_report_generator")
		}
        server = @{
            # everything from repo legimi.server
            group = @("sync", "catalogue","download_svc","mobile_api")
        }
        pubble = @{ 
            group=@("pubble_www","task_preinstaller_provision") 
        }
        legimi_old = @{
            group = @("task_mailing"
            #"sitemap","xml_generator","heartbeat","vfs","pubble","payments"
            )
        }

        everything_global = @{
            group = @("auth","int")
        }
        everything_de = @{
            #this is here to give an overview of what is required to publish whole de server
            group = @("config","core","task_mailing","server","www","publishapi_all",
						"admin","pubble","vfs","heartbeat",
						"libreka")
        }
        everything_pl = @{
            #this is here to give an overview of what is required to publish whole pl server
            group = @("config","core","task_mailing","server","www","publishapi_all",
						"admin","pubble","vfs","heartbeat",
						"audio", "olesiejuk_handler","payments",
						"pdw_log_exporter", "unl_word_counter")
        }

       config = @{
            appname = "_config"
            task = "files"
            before_files = {
                $name = $global:profile._name
                $name = $name.replace("_","-")
                write-host "[config.before_file] spwd: $pwd profile: $name"
                if ((test-path "Platform\sln\Config\build.ps1")) { 
                    & "Platform\sln\Config\build.ps1" $name
                }
            }
            profiles = @{
                alpha_de = @{
                    files = "Platform\sln\Config\devel.de.config|devel.config","Platform\sln\Config\env.alpha-de.json|env.alpha-de.json",':{"ASPNET_ENV":"alpha-de"}|env.json'
                }
                alpha_pl = @{
                    files = "Platform\sln\Config\devel-alpha.pl.config|devel.config","?Platform\sln\Config\env.alpha-pl.json|env.alpha-pl.json",':{"ASPNET_ENV":"alpha-pl"}|env.json'
                }
                alpha_cn = @{
                    files = "Platform\sln\Config\alpha.cn.config|devel.config","?Platform\sln\Config\env.alpha-cn.json|env.alpha-cn.json",':{"ASPNET_ENV":"alpha-cn"}|env.json'
                }
                beta_pl = @{
                    files = "Platform\sln\Config\devel-beta.pl.config|devel.config","?Platform\sln\Config\env.beta-pl.json|env.beta-pl.json",':{"ASPNET_ENV":"beta-pl"}|env.json'
                }
                alpha_de_env = @{
                    _inherit_from = "alpha_de"
                    files = "env.alpha-intl.json|env.alpha.json",':{"ASPNET_ENV":"alpha"}|env.json'
                }
                alpha_intl = @{
                    files = "Platform\sln\Config\env.alpha-intl.json|env.alpha-intl.json",':{"ASPNET_ENV":"alpha-intl"}|env.json'
                }
                beta_intl = @{
                    files = "Platform\sln\Config\env.beta-intl.json|env.beta-intl.json",':{"ASPNET_ENV":"beta-intl"}|env.json'
                }
                prod_de = @{
                    files = "Platform\sln\Config\prod.de.config|prod.config","env.production-de.json",':{"ASPNET_ENV":"production"}|env.json'
                }
                prod_pl = @{
                    files = "Platform\sln\Config\prod.pl.config|prod.config","env.production-pl.json|env.production.json",':{"ASPNET_ENV":"production"}|env.json'
                }
                
            }                   
        }
        db_legimi = @{
			sln = "Platform\sln\Legimi.Core\Legimi.Core.DaoSvc\Legimi.Core.DaoSvc.sln"
            proj = "Platform\src\Core\Legimi.Core.Model.Migrations\Legimi.Core.Model.Migrations.csproj"   
            task = "Build","Migrate"         
            Config = "Debug"
            connectionStringName = "LegimiDb"
            efVersion = "6.1.1"
            profiles = @{
                alpha_pl = @{
                    Config = "Debug"
                    connectionStringName = ""
                    ConnectionString = "Data Source=herakles.legimi.com;Initial Catalog=legimidev;Integrated Security=true;MultipleActiveResultSets=True"               
                }
                beta_pl = @{
                    Config = "Debug"
                    connectionStringName = ""
                    ConnectionString = "Data Source=herakles.legimi.com;Initial Catalog=legimi-beta;Integrated Security=true;MultipleActiveResultSets=True"               
                }
                alpha_de = @{
                    Config = "Debug"
                    connectionStringName = ""
                    connectionString = "Data Source=legimidb.database.windows.net;Initial Catalog=legimi-de-dev;User Id=?;Password=?;MultipleActiveResultSets=True"
                }
                alpha_cn = @{
                    Config = "Debug"
                    connectionStringName = ""
                    connectionString = "Data Source=herakles.legimi.com;Initial Catalog=legimi-alpha-cn;Integrated Security=true;MultipleActiveResultSets=True"
                }
                prod_de = @{
                    connectionStringName = ""
                    connectionString = "Data Source=legimidb.database.windows.net;Initial Catalog=legimi-de-prod;User Id=?;Password=?;MultipleActiveResultSets=True"
                }
                prod_pl = @{
                   connectionStringName = ""
                    connectionString = "Data Source=legimidb.cloudapp.net;Initial Catalog=portaldb;User Id=?;Password=?;MultipleActiveResultSets=True"
                }
				preprod = @{
                    connectionStringName = "ne-legimi-preprod"
                }
                copy = @{
                    connectionStringName = "ne-legimi-copy"
                } 
                local = @{
                    connectionStringName = "ne-legimi-local"
                }
                dev = @{
                    Config="Debug"
                }
            }
        }
        auth = @{
            proj = "src\Legimi.Api.Auth\Legimi.Api.Auth.csproj"
            appname = "svc/auth"
                            
            profiles =@{
                    alpha_intl = @{
                        Config = "Debug"
                        Test = "http://?:?@alpha.legimi.com/{appname}{?_postfix}/"
                    }                
                    beta_intl = @{
                        Config = "Debug"
                        Test = "http://?:?@beta.legimi.com/{appname}{?_postfix}/"
                    }       
                    prod = @{
                    }           
                    prod_staging = @{
                            Machine = "legimi-auth-staging.azurewebsites.net"
                            baseapppath = "legimi-auth"
                            appname = ""
                            baseUrl = "legimi-auth-staging.azurewebsites.net"
                            task = "files","Deploy","test"
                            files = "env.prod-intl.json",':{"ASPNET_ENV":"prod-intl"}|env.json'
                            test = @("http://?:?@{baseUrl}",
                                    "https://?:?@{baseUrl}/api/Resolver/ResolveCountry?countryCode=pl",
                                    "https://?:?@{baseUrl}/svc/api/Resolver/ResolveCountry?countryCode=pl"
                                    "http://?:?@{baseUrl}/api/Resolver/ResolveUser?loginOrEmail=792054503@play&password=240B82"
                                )
                            before_deploy = {
                                stop-azurewebsite "legimi-auth" -slot staging -Verbose -erroraction stop 
                            }
                            after_deploy = {
                                start-azurewebsite "legimi-auth" -slot staging -Verbose -erroraction stop 
                            }
                        }
                    swap_prod = @{
                        task = "powershell"
                        azure = $true
                        baseUrl = "legimi-auth.azurewebsites.net"
                        command = {
                            if ($force -eq $null) { $force = $true }
                            #Invoke-AzureRmResourceAction -ResourceGroupName "legimi-web" -ResourceType Microsoft.Web/sites/slots -ResourceName "legimi-auth/staging" -Action slotsswap -Parameters $ParametersObject -ApiVersion 2015-07-01
                            $result = Switch-AzureWebsiteSlot -Name "legimi-auth" -Slot1 "Staging" -Slot2 "production" -force:$force
                        }            
                        test = @("http://?:?@{baseUrl}",
                                    "https://?:?@{baseUrl}/api/Resolver/ResolveCountry?countryCode=pl",
                                    "https://?:?@{baseUrl}/svc/api/Resolver/ResolveCountry?countryCode=pl"
                                    "http://?:?@{baseUrl}/api/Resolver/ResolveUser?loginOrEmail=792054503@play&password=240B82"
                                )            
                    }
                    config_prod_staging = @{
                        Machine = "legimi-auth-staging.azurewebsites.net"
                        baseapppath = "legimi-auth"
                        appname = ""
                        task = "files"
                        files = "env.production.json",':{"ASPNET_ENV":"production"}|env.json'
                    }                    
                }                           
        }
        intl_proxy = @{
            proj = "Platform\src\server\global\Legimi.Server.WebSite.Global\Legimi.Server.WebSite.Global.xproj"
            BaseDir = "c:\www\legimicom-proxy"
            stopsite = $true
            profiles = @{                
                dev = @{
                    Machine = "legimi-intl.azurewebsites.net"
                    profile = "legimi-intl.azurewebsites.net.pubxml"
                    baseapppath = ""
                    appname = ""
                    test = "http://legimi-intl.azurewebsites.net/?auto=false"
                    before_deploy = {
                        stop-azurewebsite "legimi-intl" -Verbose -ErrorAction stop
                    }
                    after_deploy = {
                        start-azurewebsite "legimi-intl" -Verbose -ErrorAction stop
                    }
                }
                dev_staging = @{
                    _inerit_from = "dev"
                    Machine = "legimi-intl-staging.azurewebsites.net"
                    profile = "legimi-intl-staging.azurewebsites.net.pubxml"
                    baseapppath = ""
                    appname = ""
                    test = "http://legimi-intl-staging.azurewebsites.net/?auto=false"
                    before_deploy = {
                        stop-azurewebsite "legimi-intl" -Verbose -ErrorAction stop -Slot "staging"
                    }
                    after_deploy = {
                        start-azurewebsite "legimi-intl" -Verbose -ErrorAction stop -Slot "staging"
                    }
                }
                swap_dev = @{
                        task = "powershell"
                        azure = $true
                        command = {
                            if ($force -eq $null) { $force = $true }
                            #Invoke-AzureRmResourceAction -ResourceGroupName "legimi-web" -ResourceType Microsoft.Web/sites/slots -ResourceName "legimi-auth/staging" -Action slotsswap -Parameters $ParametersObject -ApiVersion 2015-07-01
                            $result = Switch-AzureWebsiteSlot -Name "legimi-intl" -Slot1 "Staging" -Slot2 "production" -force:$force
                        }                        
                    }
                prod_pl = @{
                   baseapppath = "legimicom-proxy"
                   appname=""
                }
                prod_pl_staging = @{
                   baseapppath = "legimicom-proxy-staging"
                   BaseDir = "c:\www\legimicom-proxy-staging"
                   appname=""
                   test = "http://pegaz:9070/?auto=false","http://www.legimi.com/pl/ebook-dziewczyna-z-pociagu-paula-hawkins,b119675.html"
                   files = "Platform\src\server\global\Legimi.Server.WebSite.Global\url-rewrite.prod.json|url-rewrite.json"
                }
                svc_prod_pl = @{
                   _inherit_from = "prod_pl"
                   baseapppath = "legimicom-proxy"
                   appname="svc"
                }
                svc_prod_pl_staging = @{
                   _inherit_from = "prod_pl_staging"
                   Task="Build","Deploy","Files","Test"
                   BaseDir = "c:\www\legimicom-proxy-staging"
                   appname="svc"
                   test = "http://pegaz:9070/svc/sync/"
                   files = "Platform\src\server\global\Legimi.Server.WebSite.Global\url-rewrite.prod.svc.json|url-rewrite.json"
                }
            }

        }
        www = @{
            sln = "Platform\sln\Legimi.Web\Legimi.Web.MVC.sln"        
            proj = "Platform\src\server\Legimi.Server.Website.MVC\Legimi.Server.Website.MVC.csproj"
            deployprop="DeployWWW"
            #basedir = "{basedir}\www"
            #test_fixture="Platform\test\Legimi.Server.Website.MVC.Test\prod-regression-webtests.ps1"
            appname = ""
            stopsite = $false
            test_timeout = 480
            test = "{baseUrl}"
            backupExcludes = "log/", "App_Data/", "Content/UserBooksUpload/"
            profiles = @{                       
                prod_de = @{
                    test = "http://legimi-de.cloudapp.net"                
                }
                local_release = @{
                    profile = "local-release.pubxml"
                    config = "Debug"
                }
                prod_pl_staging = @{
                    BaseUrl = "https://www.legimi.pl:8080"
                    BaseDir = "c:\www\legimi-azure-www"
                    baseapppath = "legimi-azure-staging"
                    config = "Release"
                }                
                alpha_de = @{
                    config = "Beta"                    
                    test = "http://?:?@alpha.legimi.de/{?_postfix}"
                }
                alpha_pl = @{
                    config = "Beta"                    
                    test = "http://?:?@alpha.legimi.pl/{?_postfix}"
                }
                beta_pl = @{
                    config = "Beta"                    
                    test = "http://?:?@beta.legimi.pl/{?_postfix}"
                }
                alpha_cn = @{
                    config = "Beta"                    
                    test = "http://?:?@alpha.legimi.cn/{?_postfix}"
                }
            }
        }
        admin = @{
            sln = "Platform\sln\Legimi.Server\Legimi.Server.Website.Admin.sln"        
            proj = "Platform\src\server\Legimi.Server.Website.Admin\Legimi.Server.Website.Admin.csproj"
            deployprop="DeployAdmin"
            appname = ""
            test = "{baseUrl}/{appname}{?_postfix}","{baseUrl}/{appname}{?_postfix}/Account/LogOn"
            profiles = @{
                alpha_de = @{
                    BaseAppPath = "legimi-admin-dev"
                    config = "Beta"
                    baseurl = "http://alpha.legimi.de:9092"
                }
                alpha_pl = @{
                    BaseAppPath = "legimi-admin-alpha"
                    config = "Zeta"
                    baseurl = "http://alpha.legimi.pl:9092"
                    
                }
                beta_pl = @{
                    BaseAppPath = "legimi-admin-beta"
                    config = "Beta"
                    baseurl = "http://beta.legimi.pl:9092"
                }                
                prod_de = @{
                    BaseAppPath = "legimi-admin-prod"
                    config = "Release"
                    baseurl = "http://www.legimi.de:9092"
                }
                prod_de_staging = @{
                    BaseAppPath = "legimi-admin-prod"
                    config = "Release"
                    
                }
                prod_pl = @{
                    BaseAppPath = "admin"
                    config = "Release"                    
                    baseurl = "http://www.legimi.pl:9092"
                }
            }
        }
		
		######## Services
        #http://redmine.legimi.com/projects/legimi/wiki/Publish_API
		publishapi = @{
			#repo legimi.ext.services
            sln = "Platform\sln\Legimi.Server\Legimi.Server.PublishApi.sln"
            proj = "Platform\src\Server\Legimi.Server.PublishApi\Legimi.Server.PublishApi.csproj"
            appname = "svc/publish-api/"
            profiles = @{
                prod_de = @{
                    test = "http://legimi-de.cloudapp.net/svc/publish-api/","http://legimi-de.cloudapp.net/svc/publish-api/v1/book"
                }
            }
        }
        legimiwp = @{
            sln = "Platform\sln\Legimi.Server\WebsiteWP\Legimi.Server.Website.WP.sln"        
            proj = "Platform\src\server\Legimi.Server.Website.WP\Legimi.Server.Website.WP.csproj"
            #deployprop="DeployWWW"
            profiles = @{
                production = @{
                    profile = "legimiwp.pubxml"
                    username = "$legimiwp"
                    password = "DfcxcmufZgjgkC9Jao9eE8iRzqg4mXRKmTAc2MNMqdi4NtwmfESiS3JgxtQi"         
                    config = "Release"          
                }                
            }
        }
        webapi = @{
            sln = "Platform\sln\Legimi.Server\WebApi\Legimi.Server.WebApi.sln"        
            proj = "Platform\src\server\Legimi.Server.WebApi\Legimi.Server.WebApi.csproj"
            #deployprop="DeployWWW"
            profiles = @{
                beta = @{                    
                    profile = "webapi-dev.pubxml"
                    password = "?"
                    config = "Debug"                     
                }                
            }
        }
        payments =  @{
            sln = "Platform\src\Core\Legimi.Core.Payments.Api\Legimi.Core.Payments.Api.sln"        
            proj = "Platform\src\Core\Legimi.Core.Payments.Api\Legimi.Core.Payments.Api.csproj"
            deployprop="Deploypayments_hack"
            test_fixture ="Platform\src\Core\Legimi.Core.Payments.Api\test-payments.ps1"
            test = "http://www.legimi.com/svc/payments{?_postfix}"                 
            appname = "svc/payments"
            profiles =  @{                
            }
        }
        #http://redmine.legimi.com/projects/legimi/wiki/Sync_Server
		sync = @{
            sln = "Platform\sln\Legimi.Server\Legimi.Server.2010.sln"        
            proj = "Platform\src\Server\Legimi.Server.Sync\Legimi.Server.Sync.csproj"
            appname = "svc/sync"
            deployprop="Deploysync_hack"
            test_timeout = 360
            test = "{baseUrl}/{appname}{?_postfix}"
            #deployproject = "Platform\src\Server\Legimi.Server.Sync\Legimi.Server.Sync.csproj"

            test_fixture ="webtest"
            profiles =  @{ 
            }
        }
		mobile_api =  @{
            sln = "Platform\sln\Legimi.Server\MobileApi\Legimi.Server.MobileApi.sln"        
            proj = "Platform\src\Server\Legimi.Server.MobileApi.Allegro\Legimi.Server.MobileApi.Allegro.csproj"
            appname = "svc/mobile-api"
            test = "{baseUrl}/svc/mobile-api{?_postfix}/v1/sync/info"
            profiles =  @{ 
            }
        }
		olesiejuk_handler =  @{
            sln = "Platform\sln\Legimi.Server\Olesiejuk\Legimi.Server.Olesiejuk.Handler.sln"        
            proj = "Platform\src\server\Legimi.Server.Olesiejuk.Handler\Legimi.Server.Olesiejuk.Handler.csproj"
            appname = "svc/sync"
            #deployprop="Deploysync_hack"
            #deployproject = "Platform\src\Server\Legimi.Server.Sync\Legimi.Server.Sync.csproj"

            test_fixture ="webtest"
            profiles =  @{ 
                dev_staging = @{
                    test = "http://phobos.legimi.com/svc/olesiejuk-handler-staging"
                }
                dev= @{
                    test = "http://phobos.legimi.com/svc/olesiejuk-handler"
                }
                prod_staging =  @{ 
                    profile = "azure-staging.pubxml"
                    password = "?"         
                    config = "Release"   
                    test = "http://www.legimi.com/svc/olesiejuk-staging"                 
                }
                swap_prod_pl = @{
                    Task = "SwapWebsite","test"
                    ComputerName = "pegaz"
                    TargetDir = "c:\www\legimi-azure-www\svc\olesiejuk"
                    test = "http://www.legimi.com/svc/olesiejuk"
                }
            }
        }
		inpost_api =  @{
            sln = "Platform\sln\Legimi.Server\WebApi\Legimi.Server.WebApi.sln"        
            proj = "Platform\src\server\Legimi.Server.InPostPromoApi\Legimi.Server.InPostPromoApi.csproj"
            appname = "svc/sync"
            #deployprop="Deploysync_hack"
            #deployproject = "Platform\src\Server\Legimi.Server.Sync\Legimi.Server.Sync.csproj"

            test_fixture ="webtest"
            profiles =  @{ 
                dev_staging = @{
                    test = "http://phobos.legimi.com/svc/paczkomaty-staging"
                }
                dev= @{
                    test = "http://phobos.legimi.com/svc/paczkomaty"
                }
                prod_staging =  @{ 
                    profile = "azure-staging.pubxml"
                    password = "?"         
                    config = "Release"   
                    test = "http://www.legimi.com/svc/paczkomaty-staging"                 
                }
                swap_prod_pl = @{
                    Task = "SwapWebsite","test"
                    ComputerName = "pegaz"
                    TargetDir = "c:\www\legimi-azure-www\svc\olesiejuk"
                    test = "http://www.legimi.com/svc/paczkomaty"
                }
            }
        }
		#http://redmine.legimi.com/projects/legimi/wiki/Downloader_Service
		download_svc =  @{
            sln = "Platform\sln\Legimi.Server\Legimi.Server.2010.sln"        
            proj = "Platform\src\Ext\Legimi.Ext.ContentDownload\Legimi.Ext.ContentDownload.csproj"
            appname = "svc/download"
            deployprop="Deploydownloader"
            test = "{baseUrl}/{appname}{?_postfix}"
      
            test_fixture ="webtest"
            profiles =  @{ 
            }
        }
        #http://redmine.legimi.com/projects/legimi/wiki/Catalogue_Service
        catalogue = @{
            sln = "Platform\sln\Legimi.Server\Legimi.Server.2010.sln"        
            proj = "Platform\src\server\Legimi.Server.WebSite.Handlers.CatalogueService\Legimi.Server.WebSite.Handlers.CatalogueService.csproj"
            deployprop="Deploycatalogue_hack"
            test_fixture ="webtest"
            appname = "svc/catalogue"
            test = "{baseUrl}/{appname}{?_postfix}"
            
            profiles =  @{ 
                prod_staging =  @{ 
                    profile = "azure-staging.pubxml"
                    password = "?"         
                    config = "Release"   
                    test = "http://www.legimi.com/svc/catalogue-staging"                 
                }
                swap_prod_pl = @{
                    Task = "SwapWebsite","test"
                    ComputerName = "pegaz"
                    TargetDir = "c:\www\legimi-azure-www\svc\catalogue"
                    test = "http://www.legimi.com/svc/catalogue"
                }
                alpha_de = @{
                    test = "http://alpha.legimi.de/svc/catalogue{?_postfix}",
                    "https://alpha.legimi.de/svc/catalogue{?_postfix}/CatalogueService.svc/catalogue/lite2/?category=2&color=True&filter=de&lan=de&login=&sort=1&formats=5&hybrid=False&limit=24&offset=0&free=False&icon-size=296&unlimited=False&audio=0&dev=0"
                }
                alpha_pl = @{
                    test = "http://alpha.legimi.pl/svc/catalogue{?_postfix}",
                    "https://alpha.legimi.pl/svc/catalogue{?_postfix}/CatalogueService.svc/catalogue/lite2/?category=2&color=True&filter=pl&lan=pl&login=&sort=1&formats=5&hybrid=False&limit=24&offset=0&free=False&icon-size=296&unlimited=False&audio=0&dev=0"
                }
            }
        }
        
		######## Core tasks
		#http://redmine.legimi.com/projects/legimi/wiki/Workflow
		workflow = @{
            sln = "Platform\sln\Legimi.core\legimi.core.workflows\Legimi.core.workflows.sln"        
            proj = "Platform\src\core\Legimi.core.workflows\Legimi.core.workflows.csproj"
            type = "task"
            profiles = @{
                prod_pl_staging = @{
                    Host = "www.legimi.pl"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    ComputerName = "pegaz"
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        } 
		#http://redmine.legimi.com/projects/legimi/wiki/DaoSvc
		dao = @{
            sln = "Platform\sln\Legimi.core\legimi.core.daosvc\Legimi.core.daosvc.sln"        
            proj = "Platform\src\core\Legimi.core.daosvc\Legimi.core.daosvc.csproj"
            type = "task"
            appname = "dao"
            profiles = @{
                prod_pl_staging = @{
                    Host = "www.legimi.pl"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
        #http://redmine.legimi.com/projects/legimi/wiki/EventLogProcessor
		event_processor = @{
            sln = "Platform\sln\Legimi.core\legimi.core.daosvc\Legimi.Core.DaoSvc.sln"        
            proj = "Platform\src\core\Legimi.Core.EventLogProcessor\Legimi.Core.EventLogProcessor.csproj"
            type = "task"
            appname = "event-processor"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\event-processor"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\event-processor"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\event-processor"
                    TaskName = "event-processor"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		#http://redmine.legimi.com/projects/legimi/wiki/ContentDownloader
		task_content_importer = @{
            sln = "Platform\sln\Legimi.core\legimi.core.workflows\Legimi.Core.Workflows.sln"        
            proj = "Platform\src\core\Legimi.Core.ContentDownload\Legimi.Core.ContentDownload.csproj"
            type = "task"
            appname = "content-importer"
            task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\content-importer"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\content-importer"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\content-importer"
                    TaskName = "content-importer"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		storage_cleanup = @{
			#repo legimi.ext.services
            sln = "Platform\sln\Legimi.Server\legimi.server.PublishApi.sln"        
            proj = "Platform\src\Server\Legimi.Server.Storage.Cleanup.Task\Legimi.Server.Storage.Cleanup.Task.csproj"
            type = "task"
            appname = "publish-temp-cleanup"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\publish-temp-cleanup"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\publish-temp-cleanup"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\publish-temp-cleanup"
                    TaskName = "content-importer"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		task_mailing =@{ 
		    proj = "Platform\src\Ext\Legimi.Ext.Mail\Legimi.Ext.Mail.csproj"   
			appname = "mailing"			
        }	
		#http://redmine.legimi.com/projects/legimi/wiki/Deduplicator
		task_deduplicator =@{ 
			#repo legimi.ext.services
            sln = "Platform\sln\Legimi.Server\Legimi.Server.PublishApi.sln"        
            proj = "Platform\src\Server\Legimi.Server.Deduplication.Task\Legimi.Server.Deduplication.Task.csproj"   
			appname = "deduplicator"	
			task_arguments = "--service-bus"
            profiles = @{
            }			
        }	
        #http://redmine.legimi.com/projects/legimi/wiki/PreinstallerComissionHandler
        task_preinstaller_provision = @{ 
            #repo legimi
            sln = "Tools\Legimi.Tools.PreinstallerComissionHandler\Legimi.Tools.PreinstallerComissionHandler.sln"       
            proj = "Tools\Legimi.Tools.PreinstallerComissionHandler\Legimi.Tools.PreinstallerComissionHandler\Legimi.Tools.PreinstallerComissionHandler.csproj"   
            appname = "preinstaller_provision"
            task_arguments = "--service-bus --update-db"
            profiles = @{
                alpha_pl = @{
                    task_arguments = "--service-bus --update-db --include-beta-testers"
                }
            }
        }   
		#http://redmine.legimi.com/projects/legimi/wiki/ImageProcessor
		task_imageproc = @{
			#repo legimi.ext.services
            sln = "Platform\sln\Legimi.Server\legimi.server.PublishApi.sln"        
            proj = "Platform\src\Server\Legimi.Server.Images.Task\Legimi.Server.Images.Task.csproj"
            type = "task"
            appname = "image-processor"
			task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\image-processor"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\image-processor"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\image-processor"
                    TaskName = "content-importer"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		task_mobi_generator = @{
			#repo legimi.ext.services
            sln = "Platform\sln\Legimi.Server\legimi.server.PublishApi.sln"        
            proj = "Platform\src\Server\Legimi.Server.MobiGenerator.Task\Legimi.Server.MobiGenerator.Task.csproj"
            task_interval = "10m"
            task_arguments = "--service-bus"
            profiles = @{
                # this task is only needed on _de
                prod_de = @{
                }
                alpha_de = @{
                }

                # this task is disabled on other environments
                alpha_pl = @{
                    Task = "Skip"
                }                
                beta_pl = @{
                    Task = "Skip"
                }           
                prod_pl = @{
                    Task = "Skip"
                }           
                alpha_cn = @{
                    Task = "Skip"
                }           
                prod_cn = @{
                    Task = "Skip"
                }           
            }
        }
		
		######## Importer tasks
		import_virtualo = @{
            sln = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer.sln"        
            proj = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer\Legimi.Tools.Importer.csproj"
            type = "task"
            appname = "virtualo-import"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\virtualo-import"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\virtualo-import"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\virtualo-import"
                    TaskName = "virutalo-import"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		import_pdw = @{
            sln = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer.sln"        
            proj = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer\Legimi.Tools.Importer.csproj"
            type = "task"
            appname = "pdw-import"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\pdw-import"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\pdw-import"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\pdw-import"
                    TaskName = "pdw-import"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		import_olesiejuk = @{
            sln = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer.sln"        
            proj = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer\Legimi.Tools.Importer.csproj"
            type = "task"
            appname = "olesiejuk-import"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\olesiejuk-import"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\olesiejuk-import"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\olesiejuk-import"
                    TaskName = "olesiejuk-import"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		import_soniadraga = @{
            sln = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer.sln"        
            proj = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer\Legimi.Tools.Importer.csproj"
            type = "task"
            appname = "soniadraga-import"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\soniadraga-import"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\soniadraga-import"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\soniadraga-import"
                    TaskName = "soniadraga-import"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		
		######## Other tasks
		inpost_processor = @{
            sln = "Platform\sln\Legimi.Server\WebApi\Legimi.Server.WebApi.sln"        
            proj = "Platform\src\server\Legimi.Server.InPostPromoProcessor\Legimi.Server.InPostPromoProcessor.csproj"
            type = "task"
            appname = "inpost-promo-handler"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\inpost-receiver"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\inpost-receiver"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\inpost-receiver"
                    TaskName = "inpost-promo-handler"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		sitemap = @{
		    sln = "Tools\Sitemap\Legimi.Tools.Sitemap.sln"        
		    proj = "Tools\Sitemap\Legimi.Tools.SitemapCreator\Legimi.Tools.SitemapCreator.csproj"
		    type = "task"
		    appname = "sitemap"
		    profiles = @{
		        prod_de = @{
		            Task = "PublishTask"
		            config = "Release"    
		        }
		    }
		}
		xml_generator = @{ 
			#TODO support for period tasks needs to be added
            sln = "Tools\Opds\TODO.sln"        
            proj = "Tools\Opds\TODO.csproj"   
			appname = "xml-generator"	
			type = "task"			
        }
		
		######## Other periodic tasks
		# Specific for polish deployment
		pdw_log_exporter = @{
            sln = "Tools\Legimi.Tools.CopPeriodicTasks\Legimi.Tools.CopPeriodicTasks.sln"        
            proj = "Tools\Legimi.Tools.CopPeriodicTasks\Legimi.Tools.PdwLogExporter\Legimi.Tools.PdwLogExporter.csproj"
            type = "task"
            appname = "pdw-log-exporter"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\pdw-log-exporter"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\pdw-log-exporter"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\pdw-log-exporter"
                    TaskName = "pdw-log-exporter"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		unl_word_counter = @{
            sln = "Tools\Legimi.Tools.UnlWordLimitCheck\Legimi.Tools.UnlWordLimitCheck.sln"        
            proj = "Tools\Legimi.Tools.UnlWordLimitCheck\Legimi.Tools.UnlWordLimitCheck\Legimi.Tools.UnlWordLimitCheck.csproj"
            type = "task"
            appname = "unl-word-counter"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\unl-word-counter"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\unl-word-counter"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\unl-word-counter"
                    TaskName = "unl-word-counter"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		
		######## Libreka specific
		#http://redmine.legimi.com/projects/legimi/wiki/UnlChunkReporter
		#should ran as 2 separate tasks
		unl_chunks_report = @{
			sln = "Tools\Legimi.Tools.CopPeriodicTasks\Legimi.Tools.CopPeriodicTasks.sln"        
            proj = "Tools\Legimi.Tools.CopPeriodicTasks\Legimi.Tools.UnlChunkReporter\Legimi.Tools.UnlChunkReporter.csproj"
            type = "task"
            appname = "unl-chunks-report"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\unl-chunks-report"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\unl-chunks-report"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\unl-chunks-report"
                    TaskName = "pdw-log-exporter"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
		}
		#http://redmine.legimi.com/projects/legimi/wiki/LibrekaReportGenerator
		libreka_report_generator = @{
			sln = "Tools\Legimi.Tools.CopPeriodicTasks\Legimi.Tools.CopPeriodicTasks.sln"        
            proj = "Tools\Legimi.Tools.CopPeriodicTasks\Legimi.Tools.LibrekaReportGenerator\Legimi.Tools.LibrekaReportGenerator.csproj"
            type = "task"
            appname = "libreka-report-generator"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\libreka-report-generator"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\periodic\libreka-report-generator"
                    SourceDir = "c:\www\legimi-azure-www\_deploy\webdeploy\libreka-report-generator"
                    TaskName = "pdw-log-exporter"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
		}
		
		######## Audio tasks
		#need 2 instances, how to achieve this?
		#does zeus support web publish?
		#http://redmine.legimi.com/projects/synchrobooki/wiki/Syntezator_mowy_-_lgm-audio-generatorexe
		audio_generator = @{
			sln = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.sln"        
            proj = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio\Legimi.Tools.Audio.Generator.csproj"
            type = "task"
            appname = "audio-generator"
			task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "zeus.legimi.com"
                    Site = "legimi-azure-deployment\audio-generator"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "F:\www-release\tasks\audio-generator"
                    SourceDir = "F:\www-release\_deploy\web_deploy\audio-generator"
                    TaskName = "audio-generator"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		#need 2 instances, how to achieve this?
		#does zeus support web publish?
		#http://redmine.legimi.com/projects/synchrobooki/wiki/Rozpoznawanie_mowy_-_lgm-audio-recognizerexe
		audio_recognizer = @{
			sln = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.sln"        
            proj = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio\Legimi.Tools.Audio.Recognizer.csproj"
            type = "task"
            appname = "audio-recognizer"
            task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "zeus.legimi.com"
                    Site = "legimi-azure-deployment\audio-recognizer"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "F:\www-release\tasks\audio-recognizer"
                    SourceDir = "F:\www-release\_deploy\web_deploy\audio-recognizer"
                    TaskName = "audio-generator"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		#http://redmine.legimi.com/projects/synchrobooki/wiki/Szyfrowanie_audio_-_lgm-audio-encryptorexe
		audio_encryptor = @{
			sln = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.sln"        
            proj = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.Encryptor\Legimi.Tools.Audio.Encryptor.csproj"
            type = "task"
            appname = "audio-encryptor"
            task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\audio-encryptor"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\audio-encryptor"
                    SourceDir = "C:\www\legimi-azure-www\_deploy\webdeploy\audio-encryptor"
                    TaskName = "audio-encryptor"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		#http://redmine.legimi.com/projects/synchrobooki/wiki/Zipowanie_audio_-_lgm-zipperexe
		audio_zipper = @{
			sln = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.sln"        
            proj = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.ZipCreator\Legimi.Tools.Audio.ZipCreator.csproj"
            type = "task"
            appname = "audio-zipper"
			task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\audio-zipper"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\audio-zipper"
                    SourceDir = "C:\www\legimi-azure-www\_deploy\webdeploy\audio-zipper"
                    TaskName = "audio-zipper"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		#http://redmine.legimi.com/projects/synchrobooki/wiki/Heurystyczne_%C5%82%C4%85czenie_audiobook%C3%B3w_z_ebookami_-_lgm-audio-matchexe
		audio_matcher = @{
			sln = "Tools\Legimi.Tools.Importer\Legimi.Tools.Importer.sln"        
            proj = "Tools\Legimi.Tools.Importer\Legimi.Tools.Audiobook.Matcher\Legimi.Tools.Audiobook.Matcher.csproj"
            type = "task"
            appname = "audio-matcher"
            task_arguments = "--service-bus"
            task_command = "lgm-audio-match.exe"
            task_force = $true
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\audio-matcher"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\audio-matcher"
                    SourceDir = "C:\www\legimi-azure-www\_deploy\webdeploy\audio-matcher"
                    TaskName = "audio-matcher"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		#http://redmine.legimi.com/projects/synchrobooki/wiki/Wykrywanie_obcoj%C4%99zycznych_wyraz%C3%B3w_-_word-detectorexe
		foreign_words = @{
			sln = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.sln"        
            proj = "Tools\Legimi.Tools.ForeignWordsDetector\Legimi.Tools.ForeignWordsDetector\Legimi.Tools.ForeignWordsDetector.csproj"
            type = "task"
            appname = "foreign-words"
			task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\foreign-words"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\foreign-words"
                    SourceDir = "C:\www\legimi-azure-www\_deploy\webdeploy\foreign-words"
                    TaskName = "audio-encryptor"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		#http://redmine.legimi.com/projects/synchrobooki/wiki/Tool_do_generowania_zawatermarkowanego_audio_-_lgm-audio-watermarkexe
		audio_wm = @{
			sln = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.sln"        
            proj = "Tools\Legimi.Tools.Audio\Legimi.Tools.Audio.WatermarkApplicator\Legimi.Tools.Audio.WatermarkApplicator.csproj"
            type = "task"
            appname = "audio-watermark"
            task_arguments = "--service-bus"
            profiles = @{
                prod_pl_staging = @{
                    Task = "PublishTask"
                    Host = "www.legimi.pl"
                    Site = "legimi-azure-deployment\audio-watermark"
                    config = "Release"        
                    password = "?"         
                }
                swap_prod_pl = @{
                    Task = "SwapTask"
                    ComputerName = "pegaz"
                    TargetDir = "C:\www\legimi-azure-www\tasks\audio-watermark"
                    SourceDir = "C:\www\legimi-azure-www\_deploy\webdeploy\audio-watermark"
                    TaskName = "audio-watermark"                    
                }
                preprod_staging = @{
                    config = "Devel"
                }
            }
        }
		
		
		######## 
		heartbeat = @{
            sln = "Tools\Legimi.Tools.HeartBeat\Legimi.Tools.Heartbeat.sln"        
            proj = "Tools\Legimi.Tools.HeartBeat\Legimi.Tools.Heartbeat\Legimi.Tools.Heartbeat.csproj"
            appname = "svc/heartbeat"
            stopsite = $true
            profiles = @{
                prod_pl_staging = @{
                    profile = "prod-staging.pubxml"
                    password = "?"         
                    config = "Release"
                    test = "http://www.legimi.com/svc/heartbeat-staging/heartbeat.svc/details/txt"
                }
                prod_release = @{
                    profile = "prod.pubxml"
                    password = "?"         
                    config = "Release"
                    test = "http://www.legimi.com/svc/heartbeat/heartbeat.svc/details/txt"
                }
                swap_prod_pl = @{
                    Task = "SwapWebsite","test"
                    ComputerName = "pegaz"
                    TargetDir = "c:\www\legimi-azure-www\svc\heartbeat"
                }
            }
        }
        task_heartbeat_crawler = @{            
            sln = "Tools\Legimi.Tools.HeartBeat\Legimi.Tools.HeartBeat.sln"        
            proj = "Tools\Legimi.Tools.HeartBeat\Legimi.Tools.Heartbeat.Crawler\Legimi.Tools.Heartbeat.Crawler.csproj"            
            type = "task"
            appName = "heartbeat-crawler"
            #deployprop = "DeploySolr"
            TaskName = "heartbeat-crawler"       
            TaskDir = "periodic"             
        }
		
		######## Obsolete
        vfs_obsolete = @{
            sln = "Platform\sln\Legimi.Core\Legimi.Core.Storage.Api\Legimi.Core.Storage.Api.sln"        
            proj = "Platform\src\Core\Legimi.Core.Storage.Vfs.Api\Legimi.Core.Storage.Vfs.Api.xproj"
            deployprop = "DeployVfs"
            msbuild = "c:\Program Files (x86)\MSBuild\14.0\Bin\msbuild.exe"
            profiles = @{
                dev = @{
                    profile = "dev-demeter.pubxml"
                    password = "?"         
                    config = "Debug"                    
                } 
                local_dev = @{
                    profile = "local-dev.pubxml"
                    config = "Debug"      
                    msbuildprops = @{ 
                        PublishUrl = "c:\test"
                    }              
                }               
                local_release = @{
                    profile = "local-release.pubxml"
                    config = "Debug"                    
                }    
                prod_pl = @{
                    profile = "legimi-prod.pubxml"
                    password = "?"         
                    config = "Release"
                    test = "http://www.legimi.com/svc/vfs/"                    
                } 
                prod_pl_staging = @{
                    profile = "legimi-prod-staging.pubxml"
                    password = "?"         
                    config = "Release"              
                    test = "http://www.legimi.com/svc/vfs-staging/"                          
                }    
                swap_prod_pl = @{
                    Task = "SwapWebsite","test"
                    ComputerName = "pegaz"
                    TargetDir = "c:\www\legimi-azure-www\svc\vfs"
                    test = "http://www.legimi.com/svc/vfs/"
                }      
            }
        }
        publishapi_obsolete = @{
            deployprop = "DeployPublishApi"
            sln = "Legimi.PublishApi.sln"        
            proj = "src\Legimi.Api.Publishing\Legimi.Api.Publishing.xproj"
            appname = "svc/api/v4/publishing"
            test = ""
            profiles = @{                                
            }
        }
        drmserver_obsolete = @{
            sln = "Platform\sln\Legimi.Ext\Legimi.Services.sln"        
            proj = "Platform\src\Ext\Legimi.Ext.DRMServer.Services\Legimi.Ext.DRMServer.Services.csproj"
            deployprop="Deploydrmserver"
            test_fixture="webtest"
            appname = "svc/api/v3/drmserver"
            profiles = @{              
                dev = @{
                    profile = "dev.pubxml"
                    #profile = "ne-dev-deimos.pubxml"
                    config = "Debug"
                    password = "?"
                    test = @(
                    	"http://beta.legimi.com/svc/api/v3/drmserver/version.txt"
						"http://beta.legimi.com/svc/api/v3/drmserver/test.aspx"
					)
                }
                dev_staging = @{
					 test = @(
                    	"http://beta.legimi.com/svc/api/v3/drmserver-staging/version.txt"
						"http://beta.legimi.com/svc/api/v3/drmserver-staging/test.aspx"
					)
                }
              
                prod_pl_staging = @{
                    profile = "azure-staging.pubxml"
                    password = "?"         
                    config = "Release"   
                    test = @("http://www.legimi.com/svc/api/v3/drmserver-staging/test.aspx"
                             "https://www.legimi.com/svc/api/v3/drmserver-staging/PromoService.svc/GetCurrentPromoBook?callback=jsonp1434437411171&aff=&affId=3027"
                             "http://www.legimi.com/svc/api/v3/drmserver-staging/PromoService.svc/GetCurrentPromoBook?callback=jsonp1434437411171&aff=&affId=3027"
                             )
                }
                prod_pl = @{
                    profile = "azure-release.pubxml"
                    password = "?"         
                    config = "Release"   
                    test = @("http://www.legimi.com/svc/api/v3/drmserver/test.aspx"
                             "https://www.legimi.com/svc/api/v3/drmserver/PromoService.svc/GetCurrentPromoBook?callback=jsonp1434437411171&aff=&affId=3027"
                             "http://www.legimi.com/svc/api/v3/drmserver/PromoService.svc/GetCurrentPromoBook?callback=jsonp1434437411171&aff=&affId=3027"
                             )
                }
                 swap_prod_pl = @{
                    Task = "SwapWebsite","test"
                    ComputerName = "pegaz"
                    TargetDir = "c:\www\legimi-azure-www\svc\api\v3\drmserver"
                    test = @("http://www.legimi.com/svc/api/v3/drmserver/test.aspx"
                             "https://www.legimi.com/svc/api/v3/drmserver/PromoService.svc/GetCurrentPromoBook?callback=jsonp1434437411171&aff=&affId=3027"
                             "http://www.legimi.com/svc/api/v3/drmserver/PromoService.svc/GetCurrentPromoBook?callback=jsonp1434437411171&aff=&affId=3027"
                             )
                }
                backup_prod_pl = @{
                    Task = "Backup"
                    ComputerName = "pegaz"
                    TargetDir = "c:\www\legimi-azure-www\svc\api\v3\drmserver"
                }
            }
        }
        pubble_www = @{
            sln = "Platform\sln\Legimi.Pubble\Legimi.Pubble.sln"
            proj = "Platform\src\Pubble\Legimi.Pubble.Web\Legimi.Pubble.Web.csproj"
            appname = ""            
            deployprop= "DeployPubble"
            Task="Files","Deploy"
            profiles = @{
                dev = @{
                    BaseAppPath = "legimi-pubble-beta"
                    Config = "devel"
                    Test = "http://phobos:8083/"
                }
                alpha_de = @{
                    BaseAppPath = "legimi-pubble-dev"
                    Config = "devel"
                    Test = "http://valkyria:8083/"
                }
                alpha_pl = @{
                    BaseAppPath = "legimi-pubble-alpha"
                    Config = "devel"
                    Test = "http://phobos:8083/"
                }
                beta_pl = @{
                    BaseAppPath = "legimi-pubble-beta"
                    Config = "devel"
                    Test = "http://phobos:10083/"
                }
                prod_de = @{
                    BaseAppPath = "legimi-prod-pubble"
                    Config = "Release"
                    Test = "http://www.legimi.de:8083/"
                }
                prod_pl = @{
                    BaseAppPath = "legimipubble"
                    Config = "Release"
                    Machine = "legimipubble{?_postfix}.scm.azurewebsites.net"
                    Test = "http://legimipubble{?_postfix}.azurewebsites.net"
                    Files = "env.production.json",":{ 'ASPNET_ENV': 'production' }|env.json"
                }
                prod_pl_staging = @{
                    _inherit_from = "prod_pl"
                    _postfix = "-staging"                                        

                    BaseAppPath = "legimipubble"
                    Config = "Release"
                    Machine = "legimipubble{?_postfix}.scm.azurewebsites.net"
                    Test = "http://legimipubble{?_postfix}.azurewebsites.net"
                    Files = "env.production.json",":{ 'ASPNET_ENV': 'production' }|env.json"
                }
                swap_prod_pl = @{
                    task = "powershell"
                        azure = $true
                        command = {
                            if ($force -eq $null) { $force = $true }
                            #Invoke-AzureRmResourceAction -ResourceGroupName "legimi-web" -ResourceType Microsoft.Web/sites/slots -ResourceName "legimi-auth/staging" -Action slotsswap -Parameters $ParametersObject -ApiVersion 2015-07-01
                            $result = Switch-AzureWebsiteSlot -Name "legimipubble" -Slot1 "Staging" -Slot2 "production" -force:$force
                        }       
                }
            }
            
        }

        tool_delivery_cop = @{
            proj = "Platform\test\Legimi.Core.DeliveryTestCop.Publisher\Legimi.Core.DeliveryTestCop.Publisher.csproj"
            sln = "Platform\sln\Legimi.core\legimi.core.workflows\Legimi.core.workflows.sln"        
        }
    }
}

return $publishmap
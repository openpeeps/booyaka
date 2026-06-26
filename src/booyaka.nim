#
# This is the main file for the Supranim application.
#
# It initializes the application, loads configurations,
# and sets up the necessary services and middlewares.
#
import std/[os, tables]

import pkg/supranim
import pkg/supranim/core/paths

import ./app/[structs, cli_commands]

#
# Init core modules using `init` macro
#
var customCSSPath = getCurrentDir() / "assets" / "style.css"

App.init(skipLocalConfig = true) do:
  # Booyaka does not use the default Supranim configuration
  # loading mechanism, so we define the required `server` config here.
  #
  # This is necessary for the application to run, and will be
  # overridden by the user's local configuration when they run the app.
  App.configs = newOrderedTable[string, YamlObject]()
  let serverConfig = parseYaml("""
type: "AF_INET"
port: 8000
address: "127.0.0.1"
threads: 1""")
    
  # setup tim configuration with defaults
  let timConfig = parseYaml("""
source: ./templates
output: ./storage/templates
indent: 2
sync: false
""")

  # setup booyaka runtime config for preloading
  # user-defined static assets in production
  if fileExists(customCSSPath):
    let booyakaRuntimeLoader = parseYaml("""
preload_assets: true
""")
    App.configs["runtime"] = booyakaRuntimeLoader
  App.configs["server"] = serverConfig
  App.configs["tim"] = timConfig
  
App.cli do:
  new path(directory), ?bool("--json"):
    ## Create a new Booyaka project in the specified directory

  start path(directory), ?bool("--sync"), ?port("--port"):
    ## Init the app with the given installation path

  build path(directory):
    ## Generate static HTML website

#
# Initialize available Service Providers.
#
# Configuration files are defined as YAML in the
# `config/` directory.
#
App.services do:
  # init Logger Service
  logger.init()

  # init Tim Engine
  tim.init(
    App.config("tim.source").getStr,
    App.config("tim.output").getStr,
    supranim.basePath,
    global = %*{
      "isDev": (when defined release: false else: true),
      "enableMarkdownSync": App.config("tim.sync").getBool,
      "browserSync": {
        "appPort": App.config("server.port").getInt,
      }
    }
  )

  # init Search Service
  search.init(App)

  # init Markdown Service
  markdown.init(App)

  when defined release:
    # init static assets
    assets.embedDirectory("assets", "assets")
    
    # embed Tim Engine templates directly into the binary for production
    assets.embedDirectory("templates/layouts", "templates/layouts")
    assets.embedDirectory("templates/views", "templates/views")
    assets.embedDirectory("templates/partials", "templates/partials")

    # embed Tabler SVG icons directly into the binary for production
    assets.embedDirectory("storage/icons", "storage/icons")

when defined release:
  # Preload embedded assets into memory for faster access in production
  assets.preloadBundle("assets")
  assets.preloadBundle("storage/icons")

  assets.preloadBundle("templates/layouts")
  assets.preloadBundle("templates/views")
  assets.preloadBundle("templates/partials")

  App.withAssetsHandler:
    proc (req: var Request, res: var Response, hasFoundResource: var bool) =
      # Serve static assets from the embedded StaticBundle
      req.sendEmbeddedAsset(req.path, res.getHeaders(), hasFoundResource)
      if not hasFoundResource:
        # If not found in embedded assets, try serving from
        # the local `/assets` directory
        if req.path.startsWith("/assets/"):
          hasFoundResource =
            req.sendAssets(booyakaProjectPath, req.path, res.getHeaders())

#
# Starts the application. This will start the HTTP
# server and listen for incoming requests.
#
# The application will be available at the specified port.
#
App.run do:
  # Booyaka WebSocket endpoint for live-reloading.
  when defined supraNative:
    discard # TODO
  else:
    if enableBrowserSync:
      App.server.registerCallback("/ws",
        proc (req: ptr evhttp_request, arg: pointer) {.cdecl.} =
          discard websocketUpgrade(req, onOpenCallback, nil, onClose, onError)
        )

#
# This is the main file for the Supranim application.
#
# It initializes the application, loads configurations,
# and sets up the necessary services and middlewares.
#
import std/os

import pkg/[supranim, nyml]
import pkg/kapsis/[runtime, cli]

import ./app/structs

#
# Init core modules using `init` macro
#
App.init()

# Define CLI commands for the application
proc startCommand(v: Values) =
  ## Kapsis `init` command handler
  initStartCommand(v, createDirs = false)
  let configPath = absolutePath($(v.get("directory").getPath)) / "booyaka.config"
  let port = 
    if v.has("--port"): v.get("--port").getPort
    else: 8080.Port
  if fileExists(configPath & ".yml"):
    globalBooyakaConfig = fromYaml(readFile(configPath & ".yml"), BooyakaConfig)
  elif fileExists(configPath & ".yaml"):
    globalBooyakaConfig = fromYaml(readFile(configPath & ".yaml"), BooyakaConfig)
  elif fileExists(configPath & ".json"):
    globalBooyakaConfig = fromJson(readFile(configPath & ".json"), BooyakaConfig)
  else:
    display("No Booyaka Config found in the current directory (.yml/.yaml/.json)")
    QuitFailure.quit

proc newCommand(v: Values) =
  ## Create a new Booyaka project
  let dirPath = absolutePath($(v.get("directory").getPath))

App.cli do:
  new path(directory):
    ## Create a new Booyaka project in the specified directory
  start path(directory), bool(--sync), ?port(--port):
    ## Init the app with the given installation path

#
# Initialize available Service Providers.
#
# Configuration files are defined as YAML in the
# `config/` directory.
#
App.services do:

  # init Tim Engine
  tim.init(
    App.config("tim.source").getStr,
    App.config("tim.output").getStr,
    supranim.basePath,
    global = %*{
      "isDev": (when defined release: false else: true),
      "browserSync": {
        "appPort": App.config("server.port").getInt,
      },
      "share_options": [
        {
          "title": "Copy Text",
          "description": "Copy multi-line text for LLMs",
          "url": ""
        },
        {
          "title": "Copy Markdown",
          "description": "Content as Markdown for LLMs",
          "url": ""
        },
        {"divider": true},
        {
          "title": "ChatGPT",
          "description": "Opens ChatGPT with page content",
          "url": "https://chat.openai.com"
        },
        {
          "title": "Claude",
          "description": "Ask Claude AI with page content",
          "url": "https://claude.ai"
        },
        {
          "title": "DeepSeek",
          "description": "Ask DeepSeek AI with page content",
          "url": "https://deepseek.com"
        },
        {
          "title": "DuckAI",
          "description": "Ask DuckDuckGo AI with page content",
          "url": "https://duck.ai"
        },
        {
          "title": "Microsoft Copilot",
          "description": "Ask Microsoft Copilot with page content",
          "url": "https://copilot.microsoft.com/"
        },
      ],
      "homepage_cover": "/assets/photo-1579169703977-e4575236583c.jpeg",
      "login_cover": "https://images.unsplash.com/flagged/photo-1562061162-254644341e89?q=80&w=1740&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
    }
  )

  # init Search Service
  search.init(App)

  # init Markdown Service
  markdown.init(App)

  # init static assets
  assets.embedAssets("assets")

App.withAssetsHandler:
  proc (req: var Request, res: var Response, hasFoundResource: var bool) =
    # Serve static assets from the embedded StaticBundle
    req.sendEmbeddedAsset(req.path, res.getHeaders(), hasFoundResource)

#
# Starts the application. This will start the HTTP
# server and listen for incoming requests.
#
# The application will be available at the specified port.
#
App.run do:
  # Booyaka WebSocket endpoint for live-reloading
  server.addCallback("/ws",
    proc (req: ptr evhttp_request, arg: pointer) {.cdecl.} =
      discard websocketUpgrade(req, onOpenCallback, nil, onClose, onError)
    )
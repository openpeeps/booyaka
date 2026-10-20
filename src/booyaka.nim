#
# This is the main file for the Booyaka application.
#
# It initializes the application, loads configurations,
# and sets up the necessary services and middlewares.
#
import std/[os, tables]

import pkg/supranim
import pkg/supranim/core/paths
import pkg/powpow as pw

import ./app/[structs, cli_commands]

var customCSSPath = getCurrentDir() / "assets" / "style.css"

initApp(skipLocalConfig = true):
  config do:
    # Booyaka does not use the default Supranim configuration
    # loading mechanism. Defaults live in the merged
    # `src/booyaka.config.toml`, baked into the binary at compile
    # time; at startup it is split into the per-area config objects
    # (`[app]` -> `App.configs["app"]`, `[tim]` -> `App.configs["tim"]`).
    # Everything stays in memory: nothing is read from files at runtime,
    # and `new`/`start`/`build` never create a config directory.
    const bkDefaultConfig = staticRead(basePath / "booyaka.config.toml")
    let mergedConfig = parseConfiguration(".toml", bkDefaultConfig)
    App.configs = newOrderedTable[string, Configuration]()
    for area in mergedConfig.tomlDoc.tableVal.keys:
      let sub = mergedConfig.tomlDoc.tableVal[area]
      if sub.kind == tvkTable:
        App.configs[area] = Configuration(format: cfgToml, tomlDoc: sub)

    # setup booyaka runtime config for preloading
    # user-defined static assets in production
    if fileExists(customCSSPath):
      App.configs["runtime"].putBool("preload_assets", true)

  cli do:
    new path(project), ?bool("--json"):
      ## Create a new Booyaka project in the specified directory

    theme string(name):
      ## Create a new blank Booyaka theme in ./<name>

    start path(project), ?bool("--sync"), ?port("--port"), ?bool("--devMode"):
      ## Init the app with the given installation path

    build path(project):
      ## Generate static HTML website

  services do:
    # init Logger Service
    logger.init()

    # init Tim Engine
    tim.init(
      App.config("tim.source").getStr,
      App.config("tim.output").getStr,
      if booyakaProjectPath.len > 0: booyakaProjectPath else: supranim.basePath,
      global = %*{
        "isDev": (when defined release: false else: true),
        "enableMarkdownSync": App.config("tim.sync").getBool,
        "browserSync": {
          "appPort": App.config("app.server.port").getInt,
        }
      },
      activeTheme = activeThemeName(),
      fallbackTheme = defaultThemeName
    )

    # init Search Service
    search.init(App)

    # init Markdown Service
    markdown.init(App)

  assets "assets":
    when defined release:
      # Note: theme assets are NOT embedded as servable files. The embedded
      # default theme bundle only seeds `<project>/themes/default/`; the
      # built site and the dev server always read assets from the project.
      # (Tabler SVG icons for `icon()` are still embedded below.)

      # embed Tim Engine default theme directly into the binary for production.
      # Project themes resolve from `<project>/themes/` at runtime; the embedded
      # bundle seeds `themes/default/` into projects missing it.
      assets.embedDirectory("themes/default", "themes/default")

      # embed Tabler SVG icons directly into the binary for production
      assets.embedDirectory("storage/icons", "storage/icons")

      # Preload embedded resources into memory (default theme bundle used for
      # seeding `themes/` into projects; icons used by `icon()` in templates)
      assets.preloadBundle("storage/icons")

      assets.preloadBundle("themes/default")

#
# Starts the application. This will start the HTTP
# server and listen for incoming requests.
#
# The application will be available at the specified port.
#
App.run do:
  # Booyaka WebSocket endpoint for live-reloading.
  if enableBrowserSync:
    App.server.registerCallback("/ws",
      proc (req: HttpRequest, res: HttpResponse) {.gcsafe.} =
        {.gcsafe.}:
          discard websocketUpgrade(res, req, onOpen = onOpenCallback,
                        onClose = onClose, onError = onError)
    )

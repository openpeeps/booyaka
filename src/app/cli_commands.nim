import std/[os, sequtils, strutils, tables]
from std/net import Port

import pkg/openparser/[json, yaml]
import pkg/supranim/core/[application, paths]
import pkg/kapsis/[runtime, cli]
import pkg/kapsis/interactive/prompts

import pkg/tim
import pkg/tim/engine/parser
import pkg/vancode/interpreter/[ast, codegen]

import ./structs
import ../service/provider/[markdown, tim]

const tpl = staticRead(storagePath / "stubs" / "template_booyaka.config.yaml")
  # a static template for the default Booyaka config file, used when creating new projects

# Define CLI commands for the application
proc startCommand*(v: Values) =
  ## Kapsis `init` command handler
  initStartCommand(v, createDirs = false)
  let
    projectPath = absolutePath($(v.get("directory").getPath))
    configPath = projectPath / "booyaka.config"
    assetsPath = projectPath / "assets"
    port = 
      if v.has("--port"): v.get("--port").getPort
      else: 3000.Port

  enableBrowserSync = v.has("--sync")
  # Set the server port in the application configuration
  App.configs["server"].put("port", newYamlInteger(port.int))
  App.configs["tim"].put("sync", newYamlBoolean(enableBrowserSync))

  if fileExists(configPath & ".yml"):
    globalBooyakaConfig = parseYAML(readFile(configPath & ".yml"), BooyakaConfig)
  elif fileExists(configPath & ".yaml"):
    globalBooyakaConfig = parseYAML(readFile(configPath & ".yaml"), BooyakaConfig)
  elif fileExists(configPath & ".json"):
    globalBooyakaConfig = fromJson(readFile(configPath & ".json"), BooyakaConfig)
  else:
    display("No Booyaka Config found in the current directory (.yml/.yaml/.json)")
    QuitFailure.quit
  
  if dirExists(assetsPath):
    # if the current Booyaka project provides a custom `assets` directory
    # we copy its contents into application's memory filesystem
    discard # TODO

  globalBooyakaConfig.ensureLeadingSlash()
  booyakaProjectPath = configPath.parentDir

proc newCommand*(v: Values) =
  ## Create a new Booyaka project in the specified directory
  ## If the directory is not empty, the command will fail with an error message.
  let dirPath = absolutePath($(v.get("directory").getPath))
  if dirExists(dirPath):
    # checking if the directory is empty
    if walkDir(dirPath).toSeq().len > 0:
      displayError("Directory is not empty.", quitProcess = true)
  if v.has("--json"):
    writeFile(dirPath / "booyaka.config.json", parseYaml(tpl).toJson())
  else:
    writeFile(dirPath / "booyaka.config.yaml", tpl)

proc buildCommand*(v: Values) =
  ## Build the app for production (not implemented yet)
  let app = appInstance()
  let getInstallationPath = app.applicationPaths.getInstallationPath
  let contentPath = getInstallationPath / "contents"
  let dbPath = getInstallationPath / "booyaka.db"
  let searchPath = getInstallationPath / "booyaka.search.db"
  let buildPath = getInstallationPath / "_build"
  app.initMarkdownInstance(dbPath)
  markdown.scanMarkdownFiles(contentPath, dbPath, searchPath)

  # Initialize Tim Engine for rendering templates during the build process
  # block:
  #   var timAst: Ast
  #   const booyakaLayout = staticRead(basePath / "templates" / "layouts" / "base.timl") 
  #   parser.parseScript(timAst, bookayaLayout, "")
  
  # Generate static HTML files for each markdown page
  for path, index in gMarkdownService.index:
    echo "Indexed: ", path, " -> ", index
    let mdPage = gMarkdownService.pages[index]
    if path == "/":
      writeFile(buildPath / "index.html", mdPage.content)
    else:
      writeFile(buildPath / path & ".html", mdPage.content)

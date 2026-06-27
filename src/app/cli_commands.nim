import std/[os, sequtils, strutils, tables, json]
from std/net import Port

import pkg/openparser/[json, yaml]
import pkg/supranim
import pkg/supranim/core/[application, paths]
import pkg/kapsis/[runtime, cli]
import pkg/kapsis/interactive/prompts


import ./structs
import ../service/provider/[markdown, tim, search]

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
  ## Build the app for production - generates static HTML website
  initStartCommand(v, createDirs = false)
  let
    projectPath = absolutePath($(v.get("directory").getPath))
    configPath = projectPath / "booyaka.config"

  if fileExists(configPath & ".yml"):
    globalBooyakaConfig = parseYAML(readFile(configPath & ".yml"), BooyakaConfig)
  elif fileExists(configPath & ".yaml"):
    globalBooyakaConfig = parseYAML(readFile(configPath & ".yaml"), BooyakaConfig)
  elif fileExists(configPath & ".json"):
    globalBooyakaConfig = fromJson(readFile(configPath & ".json"), BooyakaConfig)
  else:
    display("No Booyaka Config found in the current directory (.yml/.yaml/.json)")
    QuitFailure.quit

  globalBooyakaConfig.ensureLeadingSlash()
  booyakaProjectPath = configPath.parentDir

  let app = appInstance()
  let installPath = app.applicationPaths.getInstallationPath
  let contentPath = installPath / "contents"
  let dbPath = installPath / "booyaka.db"
  let searchPath = installPath / "booyaka.search.db"
  let outputPath = installPath / "_build"

  app.initMarkdownInstance(dbPath)
  scanMarkdownFiles(contentPath, dbPath, searchPath)

  tim.buildSetup(
    src = App.config("tim.source").getStr,
    output = App.config("tim.output").getStr,
    basePath = supranim.basePath,
    global = %*{
      "isDev": false,
      "enableMarkdownSync": false,
      "browserSync": {},
    }
  )

  discard existsOrCreateDir(outputPath)
  discard existsOrCreateDir(outputPath / "assets")

  let assetsSrc = supranim.basePath / "storage" / "assets"
  if dirExists(assetsSrc):
    for kind, fpath in walkDir(assetsSrc):
      if kind == pcFile:
        let (_, name, ext) = splitFile(fpath)
        try:
          copyFile(fpath, outputPath / "assets" / name & ext)
        except:
          display("Could not copy asset: " & name & ext)
  else:
    display("No built-in assets found, skipping asset copy")

  let projectAssetsCss = projectPath / "assets" / "style.css"
  if fileExists(projectAssetsCss):
    copyFile(projectAssetsCss, outputPath / "assets" / "style.css")

  for pagePath, pageHash in gMarkdownService.index:
    let mdPage = gMarkdownService.pages[pageHash]
    var mdJson = newJObject()
    if mdPage.meta != nil and mdPage.meta.kind == JObject:
      mdJson["meta"] = mdPage.meta
    else:
      mdJson["meta"] = newJObject()
    if not mdJson["meta"].hasKey("title"):
      mdJson["meta"]["title"] = newJString(mdPage.title)
    if not mdJson["meta"].hasKey("description"):
      mdJson["meta"]["description"] = newJString("")
    mdJson["title"] = newJString(mdPage.title)
    mdJson["section"] = newJString(mdPage.section)
    mdJson["content"] = newJString(mdPage.content)
    mdJson["last_updated"] = newJString(mdPage.last_updated)
    var tocJson = newJObject()
    for k, v in mdPage.toc:
      tocJson[k] = newJString(v)
    mdJson["toc"] = tocJson
    var navJson = newJObject()
    if mdPage.navigation.previous.isSome:
      var prev = newJObject()
      prev["title"] = newJString(mdPage.navigation.previous.get.title)
      prev["url"] = newJString(mdPage.navigation.previous.get.url)
      navJson["previous"] = prev
    else:
      navJson["previous"] = newJNull()
    if mdPage.navigation.next.isSome:
      var next = newJObject()
      next["title"] = newJString(mdPage.navigation.next.get.title)
      next["url"] = newJString(mdPage.navigation.next.get.url)
      navJson["next"] = next
    else:
      navJson["next"] = newJNull()
    mdJson["navigation"] = navJson
    var localData = newJObject()
    localData["markdown"] = mdJson
    localData["config"] = toJson(globalBooyakaConfig).fromJson()
    let html = tim.buildRender(pagePath, localData)
    if pagePath == "/":
      writeFile(outputPath / "index.html", html)
    else:
      let cleanPath = pagePath.strip(chars = {'/'}, leading = true)
      let pageDir = outputPath / cleanPath
      createDir(pageDir)
      writeFile(pageDir / "index.html", html)
  
  let searchEntries = spotlight().getEntries()
  var resultsArray = newJArray()
  for entry in searchEntries:
    var je = newJObject()
    je["url"] = newJString(entry.url)
    je["title"] = newJString(entry.title)
    if entry.description.isSome:
      je["description"] = newJString(entry.description.get)
    if entry.headings.isSome:
      var headings = newJArray()
      for h in entry.headings.get:
        headings.add(newJString(h))
      je["headings"] = headings
    resultsArray.add(je)
  var results = newJObject()
  results["results"] = resultsArray
  writeFile(outputPath / "results.json", $results)

  display("Build complete: " & outputPath)
  quit(0)

import std/[os, osproc, sequtils, strutils, tables, json]
from std/net import Port

import pkg/openparser/[json, yaml]
import pkg/supranim
import pkg/supranim/core/[application, paths]
import pkg/kapsis/[runtime, cli]
import pkg/kapsis/interactive/prompts
import pkg/supranim/service/storage


import ./structs
import ../service/provider/[markdown, tim, search, assets, git]
const tpl = staticRead(storagePath / "stubs" / "template_booyaka.config.yaml")
  # a static template for the default Booyaka config file, used when creating new projects
const
  themeStubThemeYaml = staticRead(storagePath / "stubs" / "theme" / "theme.yaml")
  themeStubBase = staticRead(storagePath / "stubs" / "theme" / "layouts" / "base.timl")
  themeStubLeftSidebar = staticRead(storagePath / "stubs" / "theme" / "partials" / "leftsidebar.timl")
  themeStubMain = staticRead(storagePath / "stubs" / "theme" / "partials" / "main.timl")
  themeStubRightSidebar = staticRead(storagePath / "stubs" / "theme" / "partials" / "rightsidebar.timl")
  themeStubThemeSwitcher = staticRead(storagePath / "stubs" / "theme" / "partials" / "theme-switcher.timl")
  themeStubIndex = staticRead(storagePath / "stubs" / "theme" / "views" / "index.timl")
  themeStubMarkdown = staticRead(storagePath / "stubs" / "theme" / "views" / "markdown.timl")
  themeStubSearch = staticRead(storagePath / "stubs" / "theme" / "views" / "search.timl")
  themeStub4xx = staticRead(storagePath / "stubs" / "theme" / "views" / "errors" / "4xx.timl")
  themeStub5xx = staticRead(storagePath / "stubs" / "theme" / "views" / "errors" / "5xx.timl")
  themeStubStyle = staticRead(storagePath / "stubs" / "theme" / "assets" / "style.css")
  themeStubSweetSyntaxCss = staticRead(storagePath / "stubs" / "theme" / "assets" / "sweetsyntax.css")
  themeStubSyntaxReadme = staticRead(storagePath / "stubs" / "theme" / "syntax" / "README.md")

const defaultThemeName* = "default"
  ## Name of the built-in fallback theme shipped with Booyaka

proc loadBooyaka*(projectPath: string) =
  ## Loads the Booyaka configuration from the project directory
  let configPath = projectPath / "booyaka.config"
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

proc activeThemeName*(): string =
  ## The theme selected in `booyaka.config`, defaulting to
  ## the built-in theme when unset (e.g. configs predating themes).
  let t = globalBooyakaConfig.theme.strip()
  if t.len > 0: t else: defaultThemeName

proc seedDefaultTheme*(projectPath: string) =
  ## Ensures `<project>/themes/default/` contains every file shipped with
  ## the built-in default theme. Only missing files are written, so user
  ## customizations are never overwritten. This also upgrades projects
  ## created before theme support existed. A symlinked theme dir is never
  ## written through — it is left for its devel source to manage.
  let destRoot = projectPath / "themes" / defaultThemeName
  var seeded = 0
  template seedFile(rel, content: string) =
    let dest = destRoot / rel
    if not fileExists(dest):
      createDir(dest.parentDir)
      writeFile(dest, content)
      inc seeded
  if symlinkExists(destRoot):
    display("Theme \"" & defaultThemeName & "\" is symlinked, skipping seed")
    return
  when defined release:
    const prefix = "/default/"
    let sta = staticAssets()
    for key in sta.listAssetsDir("/default"):
      if not key.startsWith(prefix):
        continue
      var content: string
      if sta.hasAsset(key):
        content = cast[string](sta.get(key))
      else:
        content = sta.directory("default")[key]
      seedFile(key[prefix.len .. ^1], content)
  else:
    let srcRoot = supranim.basePath / "themes" / defaultThemeName
    if not dirExists(srcRoot):
      displayError("Default theme not found in Booyaka sources: " & srcRoot, quitProcess = true)
    for srcPath in walkDirRec(srcRoot,
                              yieldFilter = {pcFile, pcLinkToFile},
                              followFilter = {pcDir, pcLinkToDir}):
      if not fileExists(srcPath):
        continue
      let rel = relativePath(srcPath, srcRoot)
      if extractFilename(rel).startsWith("."):
        continue
      seedFile(rel, readFile(srcPath))
  if seeded > 0:
    display("Seeded " & $seeded & " default theme file(s) into themes/" & defaultThemeName & "/")

proc initThemeDisks*(projectPath: string) =
  ## Registers runtime storage disks for public assets:
  ## `project-assets` (read/write), `theme-active` and `theme-default`
  ## (read-only). Used to serve `/assets/*` with project-first precedence.
  storage.init(App)
  storage().addDisk("project-assets",
    newLocalDriver(projectPath / "assets"))
  let active = activeThemeName()
  storage().addDisk("theme-active",
    newLocalDriver(projectPath / "themes" / active / "assets"),
    PolicyRules(readOnly: true))
  storage().addDisk("theme-default",
    newLocalDriver(projectPath / "themes" / defaultThemeName / "assets"),
    PolicyRules(readOnly: true))

proc resolvePublicAsset*(rel: string): string =
  ## Resolves a public `/assets/...` path to an absolute file path,
  ## probing project assets first, then the active theme, then the
  ## default (fallback) theme. Returns "" when no disk provides it.
  let relPath = normalizedPath(rel.strip(chars = {'/'}, leading = true))
  if relPath.len == 0 or relPath.startsWith(".") or relPath == ".." or
     relPath.startsWith(".." / ""):
    return ""
  for diskName in ["project-assets", "theme-active", "theme-default"]:
    try:
      let d = storage().rawDisk(diskName)
      if d.exists(relPath):
        let full = d.root / relPath
        if fileExists(full):
          return full
    except StorageError:
      continue
  return ""

proc copyThemeAssetsToPublic*(projectPath: string) =
  ## Copies fallback + active theme assets into `<project>/assets/`, the
  ## directory used for public serving. Same-named files are always
  ## overwritten so the served files match the active theme — customize
  ## `themes/<name>/assets/style.css` itself, not the public copy.
  ## Files the theme doesn't ship are left alone.
  let destRoot = projectPath / "assets"
  createDir(destRoot)
  var copied = 0
  proc copyThemeDir(themeName: string) =
    let assetsDir = projectPath / "themes" / themeName / "assets"
    if not dirExists(assetsDir):
      return
    for fpath in walkDirRec(assetsDir,
                            yieldFilter = {pcFile, pcLinkToFile},
                            followFilter = {pcDir, pcLinkToDir}):
      if not fileExists(fpath):
        continue
      let rel = relativePath(fpath, assetsDir)
      if extractFilename(rel).startsWith("."):
        continue
      let dest = destRoot / rel
      try:
        createDir(dest.parentDir)
        copyFile(fpath, dest)
        inc copied
      except:
        display("Could not copy theme asset: " & rel)
  copyThemeDir(defaultThemeName)
  if activeThemeName() != defaultThemeName:
    copyThemeDir(activeThemeName())
  if copied > 0:
    display("Public assets synced from theme \"" & activeThemeName() &
      "\" (" & $copied & " file(s) into assets/)")

proc scaffoldTheme*(destRoot, name, author: string): int =
  ## Writes a blank theme skeleton into `destRoot` (i.e. `./<name>/`).
  ## Returns the number of files written. The caller must ensure the
  ## destination does not exist yet.
  let themeFiles = [
    ("theme.yaml", themeStubThemeYaml),
    ("layouts/base.timl", themeStubBase),
    ("partials/leftsidebar.timl", themeStubLeftSidebar),
    ("partials/main.timl", themeStubMain),
    ("partials/rightsidebar.timl", themeStubRightSidebar),
    ("partials/theme-switcher.timl", themeStubThemeSwitcher),
    ("views/index.timl", themeStubIndex),
    ("views/markdown.timl", themeStubMarkdown),
    ("views/search.timl", themeStubSearch),
    ("views/errors/4xx.timl", themeStub4xx),
    ("views/errors/5xx.timl", themeStub5xx),
    ("assets/style.css", themeStubStyle),
    ("assets/sweetsyntax.css", themeStubSweetSyntaxCss),
    ("syntax/README.md", themeStubSyntaxReadme),
  ]
  result = 0
  for (rel, content) in themeFiles:
    let dest = destRoot / rel
    createDir(dest.parentDir)
    var text = content
    if rel == "theme.yaml":
      text = text.replace("__THEME_NAME__", name).replace("__THEME_AUTHOR__", author)
    writeFile(dest, text)
    inc result

proc themeCommand*(v: Values) =
  ## Create a new blank Booyaka theme in `./<name>`. Works anywhere —
  ## no project required. Copy or symlink the result into a project's
  ## `themes/` dir and set `theme: "<name>"` to use it.
  let name = $(v.get("name").getStr)
  if name.len == 0:
    displayError("Theme name cannot be empty.", quitProcess = true)
  for c in name:
    if c notin {'a'..'z', '0'..'9', '-', '_'}:
      displayError("Invalid theme name \"" & name &
        "\". Use lowercase letters, digits, dashes and underscores.", quitProcess = true)
  if name == defaultThemeName:
    displayError("Cannot create a theme named \"" & name &
      "\" — it is the built-in fallback theme.", quitProcess = true)
  let destRoot = getCurrentDir() / name
  if fileExists(destRoot) or dirExists(destRoot) or symlinkExists(destRoot):
    displayError("A theme already exists: " & destRoot, quitProcess = true)
  var author = ""
  try:
    let (gitName, gitCode) = execCmdEx("git config user.name")
    if gitCode == 0 and gitName.strip().len > 0:
      author = gitName.strip().replace("\"", "")
  except OSError:
    discard
  let written = scaffoldTheme(destRoot, name, author)
  display("Created a new Booyaka theme in " & destRoot & " (" & $written & " files)")
  display("Next steps:")
  display("  copy it to <project>/themes/" & name & " (or symlink it for live development)")
  display("  set `theme: \"" & name & "\"` in booyaka.config.yaml to activate it")
  quit(0)

# Define CLI commands for the application
proc startCommand*(v: Values) =
  ## Kapsis `init` command handler
  initStartCommand(v, createDirs = false)
  let
    projectPath = absolutePath($(v.get("project").getPath))
    port = 
      if v.has("--port"): v.get("--port").getPort
      else: 3000.Port

  enableBrowserSync = v.has("--sync")
  # Set the server port in the application configuration
  App.configs["server"].putInt("port", port.int)
  App.configs["tim"].putBool("sync", enableBrowserSync)

  loadBooyaka(projectPath)
  seedDefaultTheme(projectPath)
  initThemeDisks(projectPath)
  if v.has("--devMode"):
    displayWarning("Booyaka Dev-mode enabled: Serving theme assets live from source, no public copy")
  else:
    copyThemeAssetsToPublic(projectPath)

proc newCommand*(v: Values) =  ## Create a new Booyaka project in the specified directory
  ## If the directory is not empty, the command will fail with an error message.
  let dirPath = absolutePath($(v.get("project").getPath))
  if dirExists(dirPath):
    # checking if the directory is empty
    if walkDir(dirPath).toSeq().len > 0:
      displayError("Directory is not empty.", quitProcess = true)
  if v.has("--json"):
    writeFile(dirPath / "booyaka.config.json", parseYaml(tpl).toJson())
  else:
    writeFile(dirPath / "booyaka.config.yaml", tpl)
  createDir(dirPath / "assets")
  seedDefaultTheme(dirPath)
  display("Booyaka project created at: " & dirPath)

proc buildCommand*(v: Values) =
  ## Build the app for production - generates static HTML website
  initStartCommand(v, createDirs = false)
  let
    projectPath = absolutePath($(v.get("project").getPath))

  loadBooyaka(projectPath)
  seedDefaultTheme(projectPath)
  initThemeDisks(projectPath)

  let app = appInstance()
  let installPath = app.applicationPaths.getInstallationPath
  let contentPath = installPath / "contents"
  let dbPath = installPath / "booyaka.db"
  let searchPath = installPath / "booyaka.search.db"
  let outputPath = installPath / "_build"

  app.initMarkdownInstance(dbPath)
  scanMarkdownFiles(contentPath, dbPath, searchPath)
  initVersions(projectPath)

  tim.buildSetup(
    src = App.config("tim.source").getStr,
    output = App.config("tim.output").getStr,
    basePath = projectPath,
    global = %*{
      "isDev": false,
      "enableMarkdownSync": false,
      "browserSync": {},
    },
    activeTheme = activeThemeName(),
    fallbackTheme = defaultThemeName
  )

  discard existsOrCreateDir(outputPath)
  discard existsOrCreateDir(outputPath / "assets")

  proc copyDiskAssets(diskName: string) =
    ## Copies every file from a theme/project storage disk into the build
    ## output. Called fallback-first (then active theme, then project), so
    ## later copies overwrite earlier ones and project assets always win.
    var d: StorageDriver
    try:
      d = storage().rawDisk(diskName)
    except StorageError:
      return
    var entries: seq[FileMetadata]
    try:
      entries = d.list("", recursive = true)
    except StorageError:
      return
    for e in entries:
      if e.isDir or extractFilename(e.path).startsWith("."):
        continue
      let dest = outputPath / "assets" / e.path
      try:
        createDir(dest.parentDir)
        writeFile(dest, d.read(e.path))
      except:
        display("Could not copy asset: " & e.path)

  copyDiskAssets("theme-default")
  if activeThemeName() != defaultThemeName:
    copyDiskAssets("theme-active")
  copyDiskAssets("project-assets")

  proc renderPages(instance: MarkdownInstance, destPath: string,
      version = "") =
    ## Renders every page of `instance` into `destPath` as static HTML.
    ## The version switcher data links each entry to the same page in that
    ## version when it exists, falling back to the version index.
    proc switcherItems(currentSlug: string): JsonNode =
      var versions = newJArray()
      for label in @[globalBooyakaConfig.git.latest_label] & gVersionList:
        var target =
          if label == globalBooyakaConfig.git.latest_label: ""
          else: "/" & label
        if currentSlug.len > 0 and currentSlug != "/":
          let slugPath = currentSlug.strip(chars = {'/'}, leading = true)
          let hasPage =
            if label == globalBooyakaConfig.git.latest_label:
              gMarkdownService.index.hasKey(currentSlug)
            else:
              not gMarkdownVersions.isNil and gMarkdownVersions.hasKey(label) and
                gMarkdownVersions[label].index.hasKey(currentSlug)
          if hasPage:
            target = target & "/" & slugPath
        versions.add(%*{
          "label": label,
          "path": target
        })
      versions
    for pagePath, pageHash in instance.index:
      if pagePath.strip(chars = {'/'}, leading = true, trailing = true).toLowerAscii() == "llms":
        # reserved root `llms.md` only emits `/llms.txt`, never `/llms`
        continue
      let mdPage = instance.pages[pageHash]
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
      mdJson["markdownSourceJson"] = newJString(mdPage.markdownSourceJson)
      var tocJson = newJObject()
      for k, v in mdPage.toc:
        tocJson[k] = newJString(v)
      mdJson["toc"] = tocJson
      mdJson["tocHtml"] = newJString(mdPage.tocHtml)
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
      localData["version"] = %*{
        "label": version,
        "path": if version.len > 0: "/" & version else: ""
      }
      localData["versions"] = %*{
        "enable": globalBooyakaConfig.git.enable_versioning,
        "items": switcherItems(pagePath)
      }
      let html = tim.buildRender(pagePath, localData)
      if pagePath == "/":
        writeFile(destPath / "index.html", html)
      else:
        let cleanPath = pagePath.strip(chars = {'/'}, leading = true)
        let pageDir = destPath / cleanPath
        createDir(pageDir)
        writeFile(pageDir / "index.html", html)

  renderPages(gMarkdownService, outputPath)

  # emit `/llms.txt` from the root `llms.md` file when present (any case)
  var llmsSource = ""
  for kind, path in walkDir(contentPath):
    if kind == pcFile and extractFilename(path).toLowerAscii() == "llms.md":
      llmsSource = path
      break
  if llmsSource.len > 0:
    writeFile(outputPath / "llms.txt", readFile(llmsSource))

  if globalBooyakaConfig.git.enable_versioning:
    # build a static site for every semver git tag under `<output>/<tag>/`
    for tag in getSemverTags(projectPath):
      if gMarkdownVersions.isNil or not gMarkdownVersions.hasKey(tag):
        continue
      let versionPath = outputPath / tag
      discard existsOrCreateDir(versionPath)
      renderPages(gMarkdownVersions[tag], versionPath, version = tag)

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
  displaySuccess("Build complete: " & outputPath)
  quit(0)
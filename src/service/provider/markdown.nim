# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

import std/[os, tables, httpcore, strutils,
          json, options, sequtils, macros, times, net]

import pkg/checksums/sha1
import pkg/openparser/[yaml, json]
import pkg/[htmlparser, supersnappy, flatty,
              watchout, marvdown, semver, kapsis/cli]

import pkg/supranim/core/[services, application, paths]
import pkg/supranim/network/[webserver, websocket]
import pkg/supranim/support/slug
import pkg/threading/rwlock

import ./tim, ./search
import ../../app/structs

export structs

initService Markdown[Global]:
  backend do:
    type
      MarkdownInstance* = ref object
        pages*: TableRef[string, MarkdownPage] # map of markdown file paths to HTML content
        index*: TableRef[string, string] # map of original paths to hashed paths
        config*: BooyakaConfig
        version*: semver.Version = newVersion(0, 1, 0)

    var
      contentPath: string # provided when initializing the service
      buildPath: string
      partialsPath: string
      buildStaticPath: string
      watcher*: Watchout
      hasChanges : bool
      gMarkdownService* : MarkdownInstance
      wsClients: seq[ptr WebSocketConnectionImpl]
      searchInstance: SpotlightInstance
      changeLocker = createRwLock()
    let
      markdownOptions = MarkdownOptions(
        allowed: @[
          tagA, tagAbbr, tagB, tagBlockquote, tagBr,
          tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
          tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
          tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl, tagMark, tagSmall,
          tagSub, tagSup, tagDiv
        ],
        allowTagsByType: none(TagType),
        allowInlineStyle: false,
        allowHtmlAttributes: false,
        enableAnchors: true,
        htmlTableClasses: some(@["table", "table-hover"])
      )

    proc `%`(opt: Option[Time]): JsonNode =
      %*(opt.get().toUnix)

    proc toFlatty(s: var string, x: Time) =
      s.toFlatty(x.toUnix)

    proc fromFlatty(s: string, i: var int, x: var Time) =
      var unix: int64
      s.fromFlatty(i, unix)
      x = unix.fromUnix

    proc initMarkdownInstance*(app: Application, dbPath: string) =
      ## Initializes the markdown service instance, loading existing data from the database if it exists
      if fileExists(dbPath):
        gMarkdownService = fromFlatty(uncompress(readFile(dbPath)), MarkdownInstance)
      else:
        gMarkdownService = MarkdownInstance(
          pages: newTable[string, MarkdownPage](),
          index: newTable[string, string](), # map of original paths to hashed paths
        )
      search.init(app)
      searchInstance = getSpotlightInstance()

    # WebSocket Connection - Callbacks
    proc onMessageCallback(c: ptr WebSocketConnectionImpl, code: int, data: openArray[byte]) =
      {.gcsafe.}:
        if code == 0x1: # text
          let s = cast[string](data.toSeq)
          sendText(c, "echo: " & s)

    proc onOpenCallback*(c: ptr WebSocketConnectionImpl) =
      {.gcsafe.}:
        writeWith changeLocker:
          sendText(c, "Markdown Service WebSocket Connected")
          wsClients.add(c)

    proc onClose*(c: ptr WebSocketConnectionImpl, code: int, reason: string) =
      {.gcsafe.}:
        writeWith changeLocker:
          wsClients = wsClients.filterIt(it[].id != c[].id)

    proc onError*(c: ptr WebSocketConnectionImpl, err: string) =
      discard

    proc notifyClients() =
      {.gcsafe.}:
        writeWith changeLocker:
          hasChanges = false
        readWith changeLocker:
          for ws in wsClients:
            ws.sendText("1") # notify clients of change

    proc getSlugHash(basePath, path: string): (string, string) =
      # Computes the slug and its secure hash for a given markdown file path
      var k = path.replace(basePath).replace(".md").slugify(allowSlash = true)
      if k == "index": k = "/"
      result = (k, $(secureHash(k)))

    proc flattenNavigation(nav: seq[NavigationSection]): seq[BooyakaNavItem] =
      # Flattens sidebar_navigation into a single sequence of nav items
      for section in nav:
        for item in section.items:
          result.add(item)

    proc findItem[T](s: seq[T], pred: proc(x: T): bool): int =
      result = -1  # return -1 if no items satisfy the predicate
      for i, x in s:
        if pred(x):
          result = i
          break

    proc getPrevNext(nav: seq[NavigationSection], currentUrl: string): (Option[BooyakaNavItem], Option[BooyakaNavItem]) =
      # Get previous and next navigation items based on the current URL
      let flat = flattenNavigation(nav)
      let idx =
        flat.findItem(
            proc(x: BooyakaNavItem): bool =
              if currentUrl != "/":
                return x.url == "/" & currentUrl
              currentUrl == x.url
        )
      if idx == -1: return (none(BooyakaNavItem), none(BooyakaNavItem))
      let prev = if idx > 0: some(flat[idx - 1]) else: none(BooyakaNavItem)
      let next = if idx < flat.len - 1: some(flat[idx + 1]) else: none(BooyakaNavItem)
      (prev, next)

    proc parseMarkdownFile(mdInstance: MarkdownInstance, basePath,
                    path: string, hashedSlug: Option[(string, string)] = none((string, string))) = 
      # Parses a markdown file and updates the markdown instance
      var md = newMarkdown(readFile(path), markdownOptions)
      let
        # compute slug and hash
        slugHash =
          if not hashedSlug.isSome: getSlugHash(basePath, path)
          else: hashedSlug.get()
        # get previous and next navigation items
        (prev, next) = getPrevNext(globalBooyakaConfig.sidebar_navigation, slugHash[0])
        htmlContent: string = md.toHtml()   # convert markdown to HTML
      let
        meta: JsonNode = toJson(md.getHeader()).fromJson()
      searchInstance.addEntry(
        slugHash[1],
        slugHash[0],
        title =
          (if meta.kind == JObject and meta.hasKey"title":
              meta["title"].getStr()
          else: md.getTitle()),
        description = (
          if meta.kind == JObject and meta.hasKey"description":
              some(meta["description"].getStr)
            else: none(string)
          ),
        headings = some(md.getSelectorsList())
      )
      mdInstance.index[slugHash[0]] = slugHash[1]
      var sectionName: string
      for section in globalBooyakaConfig.sidebar_navigation:
        for item in section.items:
          if item.url == "/" & slugHash[0]:
            sectionName = section.name
            break
      # update the markdown instance with the new page content
      mdInstance.pages[slugHash[1]] =
        MarkdownPage(
          meta: meta,
          title: md.getTitle(),
          section: sectionName,
          content: htmlContent,
          last_updated: now().format("yyyy-MM-dd HH:mm:ss"),
          toc: md.getSelectors(),
          navigation: MarkdownPageBottomNavigation(previous: prev, next: next),
          lastEdited: some(now().toTime)
        )
      # write the parsed markdown content to disk
      # we write to a hashed filename to avoid issues with special characters in URLs and to ensure uniqueness
      let hashedPath = partialsPath / toLowerAscii(slugHash[1])  & ".html"
      writeFile(hashedPath, htmlContent) #
      hasChanges = true

    # initialize markdown service
    proc onFound(file: watchout.File) =
      # Callback when a markdown file is found
      discard

    proc onChange(file: watchout.File) =
      # Callback when a markdown file is changed
      let path = file.getPath()
      gMarkdownService.parseMarkdownFile(contentPath, path)
      notifyClients()

    proc onDelete(file: watchout.File) =
      # Callback when a markdown file is deleted
      echo "Markdown file deleted: ", file.getPath

    proc scanMarkdownFiles*(contentPath, dbPath, searchPath: string) =
      ## Scans the content directory for markdown files, parses them, and
      ## updates the markdown service index and search index accordingly.
      for path in walkDirRec(contentPath, {pcFile}):
        let fpath = path.splitFile
        if fpath.ext != ".md" or fpath.name.startsWith("!"):
          # skip non-markdown files and temporary files prefixed with "!"
          continue
        let hashedSlug = getSlugHash(contentPath, path)
        if gMarkdownService.pages.hasKey(hashedSlug[1]):
          let md = gMarkdownService.pages[hashedSlug[1]]
          if md.lastEdited.isSome and md.lastEdited.get() >= getLastModificationTime(path):
            continue # skip unchanged files
        
        # parse markdown file and update the markdown service index
        gMarkdownService.parseMarkdownFile(contentPath, path, some(hashedSlug))
      
      # write initial index to booyaka.db
      writeFile(dbPath, compress(toFlatty(gMarkdownService)))
      writeFile(searchPath, compress(toFlatty(searchInstance[])))

    # Setup the filesystem monitor
    const defaultHomePage = staticRead(storagePath / "stubs" / "index.md")
    proc init*(app: Application) =
      ## Initialize the Markdown service and start monitoring files
      contentPath = app.applicationPaths.getInstallationPath / "contents"
      buildPath = app.applicationPaths.getInstallationPath / "_build"
      partialsPath = buildPath / "partials"

      discard existsOrCreateDir(buildPath)
      discard existsOrCreateDir(buildPath / "partials")
      discard existsOrCreateDir(contentPath)
      
      if not fileExists(contentPath / "index.md"):
        # ensure there's at least an index.md to start with
        writeFile(contentPath / "index.md", defaultHomePage)

      let dbPath = app.applicationPaths.getInstallationPath / "booyaka.db"
      let searchPath = app.applicationPaths.getInstallationPath / "booyaka.search.db"
      app.initMarkdownInstance(dbPath)

      # Create a new Watchout instance to monitor markdown files
      watcher = newWatchout(@[contentPath], some("*.md"))
      watcher.onChange = onChange
      watcher.onFound = onFound
      watcher.onDelete = onDelete
      watcher.start() # in the background (new thread)

      # initial scan of existing markdown files
      scanMarkdownFiles(contentPath, dbPath, searchPath)
      
# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

import std/[os, osproc, tables, httpcore, strutils, xmltree,
          json, options, sequtils, macros, times, net, critbits]

import pkg/checksums/sha1
import pkg/[nyml, htmlparser, supersnappy, flatty, jsony,
            watchout, marvdown, semver, kapsis/cli]

import pkg/supranim/core/[servicemanager, application, paths, config]
import pkg/supranim/network/http/webserver
import pkg/supranim/network/ws/websocket
import pkg/supranim/http/[request, response, fileserver, autolink, router]

import ./tim, ./search
import ../../app/structs

import pkg/supranim/support/[nanoid, url, slug]

initService Markdown[Global]:
  backend do:
    type
      MarkdownInstance = ref object
        pages*: TableRef[string, MarkdownPage] # map of markdown file paths to HTML content
        index*: TableRef[string, string] # map of original paths to hashed paths
        config*: BooyakaConfig
        version*: semver.Version = newVersion(0, 1, 0)

    var
      contentSourcePath: string # provided when initializing the service
      watcher*: Watchout
      hasChanges: bool
      globalMarkdownService*: MarkdownInstance
      globalBooyakaConfig*: BooyakaConfig
      wsClients: seq[ptr WebSocketConnectionImpl]
      searchInstance: SpotlightInstance
    
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
        enableAnchors: true
      )

    proc `%`(opt: Option[Time]): JsonNode =
      %*(opt.get().toUnix)

    proc toFlatty(s: var string, x: Time) =
      s.toFlatty(x.toUnix)

    proc fromFlatty(s: string, i: var int, x: var Time) =
      var unix: int64
      s.fromFlatty(i, unix)
      x = unix.fromUnix

    # WebSocket Connection - Callbacks
    proc onMessageCallback(c: ptr WebSocketConnectionImpl, code: int, data: openArray[byte]) =
      {.gcsafe.}:
        if code == 0x1: # text
          let s = cast[string](data.toSeq)
          sendText(c, "echo: " & s)

    proc onOpenCallback*(c: ptr WebSocketConnectionImpl) =
      {.gcsafe.}:
        wsClients.add(c)

    proc onClose*(c: ptr WebSocketConnectionImpl, code: int, reason: string) =
      {.gcsafe.}:
        wsClients = wsClients.filterIt(it[].id != c[].id)

    proc onError*(c: ptr WebSocketConnectionImpl, err: string) =
      discard

    proc notifyClients() =
      for ws in wsClients:
        ws.sendText("1") # notify clients of change
      hasChanges = false

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
        # markdown to html
        htmlContent: string = md.toHtml()
        # retrieve page metadata
        meta: JsonNode = md.getHeader()
        # update search index
      
      searchInstance.addEntry(
        slugHash[1],
        slugHash[0],
        title =
          (if meta != nil and meta.hasKey"title":
              meta["title"].getStr
          else: md.getTitle()),
        description = (
          if meta != nil and meta.hasKey"description":
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

    # initialize markdown service
    proc onFound(file: watchout.File) =
      # Callback when a markdown file is found
      discard

    proc onChange(file: watchout.File) =
      # Callback when a markdown file is changed
      let path = file.getPath()
      globalMarkdownService.parseMarkdownFile(contentSourcePath, path)
      notifyClients()

    proc onDelete(file: watchout.File) =
      # Callback when a markdown file is deleted
      echo "Markdown file deleted: ", file.getPath

    proc getSlug*(req: var Request, res: var Response): void =
      ## A Supranim route handler to serve markdown pages based on slug
      ## This handler will be used to handle all requests to secondary pages
      ## generated from markdown files.
      {.gcsafe.}:
        let slug = req.params["slug"]
        if globalMarkdownService.index.hasKey(slug):
          render("index", local = &*{
            "markdown": globalMarkdownService.pages[globalMarkdownService.index[slug]],
            "config": toJson(globalBooyakaConfig).fromJson()
          })
        else:
          render("errors.4xx", httpCode = Http404)

    # Setup the filesystem monitor
    proc init*(app: Application) =
      ## Initialize the Markdown service and start monitoring files
      let autolinked: Autolinked =
        autolink.autolinkController("/{slug:anySlug}", HttpGet)
      app.router.registerRoute((autolinked[1], autolinked[2]), HttpGet, getSlug)

      searchInstance = getSpotlightInstance()
      contentSourcePath = app.applicationPaths.getInstallationPath / "contents"
      discard existsOrCreateDir(contentSourcePath) # ensure contents directory exists

      let booyakaDatabasePath = app.applicationPaths.getInstallationPath / "booyaka.db"
      let booyakaSearchPath = app.applicationPaths.getInstallationPath / "booyaka.search.db"
      if fileExists(booyakaDatabasePath):
        # Load existing markdown database if it exists
        globalMarkdownService = fromFlatty(uncompress(readFile(booyakaDatabasePath)), MarkdownInstance)
      else:
        # Create a new MarkdownInstance if no database exists
        globalMarkdownService = MarkdownInstance(
          pages: newTable[string, MarkdownPage](),
          index: newTable[string, string](), # map of original paths to hashed paths
        )

      # Create a new Watchout instance to monitor markdown files
      watcher = newWatchout(@[contentSourcePath], some("*.md"))
      watcher.onChange = onChange
      watcher.onFound = onFound
      watcher.onDelete = onDelete
      watcher.start() # in the background (new thread)

      # initial scan of existing markdown files
      for path in walkDirRec(contentSourcePath, {pcFile}):
        let fpath = path.splitFile
        if path.splitFile.ext != ".md": continue # only process markdown files
        if fpath.name.startsWith("!"): continue # skip files prefixed with "!"
        let hashedSlug = getSlugHash(contentSourcePath, path)
        
        if globalMarkdownService.pages.hasKey(hashedSlug[1]):
          let md = globalMarkdownService.pages[hashedSlug[1]]
          if md.lastEdited.isSome and md.lastEdited.get() >= getLastModificationTime(path):
            continue # skip unchanged files
        globalMarkdownService.parseMarkdownFile(contentSourcePath, path, some(hashedSlug))
      
      # write initial index to booyaka.db
      writeFile(booyakaDatabasePath, compress(toFlatty(globalMarkdownService)))
      writeFile(booyakaSearchPath, compress(toFlatty(searchInstance[])))
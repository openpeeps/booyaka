# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

## This Service provides Markdown parsing and rendering capabilities for the Booyaka.
## 
## It monitors the content directory for markdown files, parses them into HTML, and serves the rendered content.
## It also maintains an index of markdown files and their corresponding rendered HTML for search and navigation purposes.
## 
## Key Features:
## - Real-time monitoring of markdown files for changes, additions, and deletions using Watchout
## - Parsing markdown files into HTML using Marvdown with configurable options
## - Extraction of metadata from markdown files (e.g., title, description) for enhanced search capabilities
## - Generation of unique slugs and secure hashes for markdown file paths to ensure URL safety and uniqueness
## - Integration with the Spotlight search service to index markdown content for fast retrieval
## - WebSocket support to notify connected clients of content changes in real-time
## - Efficient handling of markdown content with caching and incremental updates to minimize processing overhead

import std/[os, tables, httpcore, strutils,
          options, sequtils, macros, times, net]

import pkg/checksums/sha1
import pkg/openparser/[yaml, json, html]
import pkg/[watchout, marvdown, semver, kapsis/cli]
import pkg/openparser/fbe

import pkg/supranim/core/[services, application, paths]
import pkg/supranim/network/[webserver, websocket]
import pkg/supranim/support/slug
import pkg/threading/rwlock

import ./tim, ./search, ./git, ./dbcodec
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
      gMarkdownVersions*: TableRef[string, MarkdownInstance]
        ## Map of version label -> MarkdownInstance, populated when
        ## `git.enable_versioning` is enabled (see `initVersionedMarkdown`)
      gVersionList*: seq[string]
        ## Sorted list of version labels (latest first) for the version switcher
      wsClients: seq[WsConnection]
      searchInstance: SpotlightInstance
      changeLocker = createRwLock()
      allowedTags = @[tagA, tagAbbr, tagB, tagBlockquote, tagBr,
                    tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
                    tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
                    tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl, tagMark, tagSmall,
                    tagSub, tagSup, tagDiv]

    var
      markdownOptions = MarkdownOptions(
        allowTagsByType: none(TagType),
        allowInlineStyle: false,
        allowHtmlAttributes: false,
        enableAnchors: true,
        htmlTableClasses: some(@["table", "table-hover"]),
        enableComponents: true,
        componentBaseDir: contentPath
      )

    proc `%`(opt: Option[Time]): JsonNode =
      %*(opt.get().toUnix)

    proc escapeHtmlText(s: string): string =
      ## Escapes HTML special characters for safe text/attribute output
      result = s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"),
                              ("\"", "&quot;"), ("'", "&#39;"))

    proc pageCardHtml(page: MarkdownPage, url: string): string =
      ## Builds the HTML card rendered for a `@<page>.md` reference
      var title = page.title
      var description = ""
      if page.meta != nil and page.meta.kind == JObject:
        if page.meta.hasKey("title"):
          title = page.meta["title"].getStr()
        if page.meta.hasKey("description"):
          description = page.meta["description"].getStr()
      result = "<div class=\"post-ref\"><a class=\"post-ref__link\" href=\"" &
        url & "\">"
      result.add("<div class=\"post-ref__body\">")
      result.add("<h3 class=\"post-ref__title\">" &
        escapeHtmlText(title) & "</h3>")
      if description.len > 0:
        result.add("<p class=\"post-ref__excerpt\">" &
          escapeHtmlText(description) & "</p>")
      result.add("</div></a></div>")

    proc findPageRef(target: string): (string, MarkdownPage) =
      ## Resolves a `@<target>.md` reference to a page (url, page). Unknown
      ## references return an empty string url so they stay as plain text.
      ## The reserved root `llms.md` (`/llms.txt` only) never resolves.
      if target.strip().toLowerAscii().strip(chars = {'/', '.'}, leading = true, trailing = false) == "llms.md":
        return ("", MarkdownPage())
      if gMarkdownService.isNil:
        return ("", MarkdownPage())
      # normalize: strip the leading slash and `.md` extension
      var refName = target.replace(".md", "")
      if refName.startsWith("/"):
        refName = refName[1 .. ^1]
      # a page can be referenced by its basename (`@tcp.md`) or its full
      # slug path (`@net/tcp.md`); iterate the index to find a match
      for slug, hash in gMarkdownService.index:
        let slugName = slug.strip(chars = {'/'})
        if slugName == refName or slugName.split('/')[^1] == refName:
          if gMarkdownService.pages.hasKey(hash):
            return ("/" & slugName, gMarkdownService.pages[hash])
      # fall back to the source file so references resolve regardless of the
      # scan order (e.g. the very first build). Parse with a local options copy
      # that has no customTransform, so resolving a reference can never recurse
      # into resolving that file's own references.
      let refPath = contentPath / target
      if fileExists(refPath):
        var opts = markdownOptions
        opts.customTransform = nil
        var md = newMarkdown(readFile(refPath), opts)
        let meta: JsonNode = toJson(md.getHeader()).fromJson()
        return ("/" & refName, MarkdownPage(meta: meta, title: md.getTitle()))
      result = ("", MarkdownPage())

    proc pageReferenceTransform(line: string): string =
      ## Custom marvdown parsing hook: replaces `@<page>.md` references with a
      ## page card when the referenced markdown file exists as a page. Unknown
      ## references (e.g. `@somebrand.md`) are left as plain text.
      result = newStringOfCap(line.len)
      var i = 0
      while i < line.len:
        if line[i] == '@' and (i == 0 or line[i - 1] != '\\'):
          var j = i + 1
          var name = ""
          while j < line.len and line[j] in {'a'..'z', 'A'..'Z', '0'..'9',
                                             '.', '_', '-', '/'}:
            name.add(line[j])
            inc j
          if name.endsWith(".md") and name.len > 3 and
             (j >= line.len or line[j] notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}):
            let (url, page) = findPageRef(name)
            if url.len > 0:
              result.add(pageCardHtml(page, url))
              i = j
              continue
        result.add(line[i])
        inc i

    proc setupMarkdownOptions() =
      ## Configures the Marvdown options based on the Booyaka configuration.
      ## Called from `initMarkdownInstance` so both `start` and `build` paths
      ## apply the same settings (allowed tags, lazy loading, page references).
      var allowedHtmlTags: seq[HtmlTag]
      if isSome(globalBooyakaConfig.content.allowedRawHtmlTags):
        allowedHtmlTags = concat(allowedTags, globalBooyakaConfig.content.allowedRawHtmlTags.get())
      else:
        allowedHtmlTags = allowedTags
      markdownOptions.allowed = allowedHtmlTags
      markdownOptions.lazyloadIframes = globalBooyakaConfig.content.lazyloadIframes
      markdownOptions.lazyloadVideos = globalBooyakaConfig.content.lazyloadVideos
      markdownOptions.lazyloadImages = globalBooyakaConfig.content.lazyloadImages
      markdownOptions.customTransform =
        if globalBooyakaConfig.content.pageReferences:
          pageReferenceTransform
        else:
          nil

    proc writeMarkdownInstanceFields(b: var Buffer, inst: MarkdownInstance) =
      b.writeField(1'u16, proc (bb: var Buffer) =
        let items =
          if inst.pages.isNil: newSeq[tuple[key: string, val: MarkdownPage]]()
          else: toSeq(pairs(inst.pages))
        writeMap[string, MarkdownPage](bb, items,
          proc (bbb: var Buffer, k: string) = bbb.writeString(k),
          proc (bbb: var Buffer, p: MarkdownPage) = bbb.writeMarkdownPage(p)))
      b.writeField(2'u16, proc (bb: var Buffer) = bb.writeStrMap(inst.index))
      b.writeField(3'u16, proc (bb: var Buffer) = bb.writeConfig(inst.config))
      b.writeField(4'u16, proc (bb: var Buffer) = bb.writeSemverVersion(inst.version))

    proc handleMarkdownInstanceField(fid: uint16, fsz: int, b: var Buffer,
                                     into: var MarkdownInstance) =
      case fid
      of 1'u16:
        into.pages = newTable[string, MarkdownPage]()
        for kv in readMap[string, MarkdownPage](b, 
            proc (bb: var Buffer): string = bb.readString(),
            proc (bb: var Buffer): MarkdownPage = bb.readMarkdownPage()):
          into.pages[kv.key] = kv.val
      of 2'u16:
        into.index = b.readStrMap()
      of 3'u16:
        into.config = b.readConfig()
      of 4'u16:
        into.version = b.readSemverVersion()
      else: discard

    proc encodeMarkdownInstance*(inst: MarkdownInstance): Buffer =
      ## Serializes a `MarkdownInstance` into an FBE payload buffer
      ## (wrap with `writeDbFile` for the signature envelope)
      result = initBuffer()
      encodeRootFrom(result, inst, writeMarkdownInstanceFields, DbCodecVersion)

    proc decodeMarkdownInstance*(b: var Buffer): MarkdownInstance =
      ## Deserializes a `MarkdownInstance` from an FBE payload buffer
      ## (unwrap with `readDbFile` first)
      result = MarkdownInstance(
        pages: newTable[string, MarkdownPage](),
        index: newTable[string, string](),
      )
      var outVer: uint32
      b.decodeRootInto(result, handleMarkdownInstanceField, outVer)

    proc initMarkdownInstance*(app: Application, dbPath: string) =
      ## Initializes the markdown service instance, loading existing data from the database if it exists
      setupMarkdownOptions()
      proc freshMarkdownService() =
        gMarkdownService = MarkdownInstance(
          pages: newTable[string, MarkdownPage](),
          index: newTable[string, string](), # map of original paths to hashed paths
        )
      var payload: Buffer
      case readDbFile(dbPath, payload)
      of dbOk:
        try:
          gMarkdownService = decodeMarkdownInstance(payload)
        except CatchableError:
          freshMarkdownService()
      else:
        # missing file (first run) or stale/foreign format (pre-FBE
        # flatty db, codec or Booyaka version mismatch): start fresh,
        # the scan below rebuilds the index
        freshMarkdownService()
      search.init(app)
      searchInstance = getSpotlightInstance()

    # WebSocket Connection - Callbacks
    proc onMessageCallback(ws: WsConnection, kind: WsFrameKind, data: openArray[byte]) =
      {.gcsafe.}:
        if kind == wsText:
          let s = cast[string](data.toSeq)
          ws.sendText("echo: " & s)

    proc onOpenCallback*(ws: WsConnection) =
      {.gcsafe.}:
        writeWith changeLocker:
          ws.sendText("Markdown Service WebSocket Connected")
          wsClients.add(ws)

    proc onClose*(ws: WsConnection, code: int, reason: string) =
      {.gcsafe.}:
        writeWith changeLocker:
          wsClients = wsClients.filterIt(it != ws)

    proc onError*(ws: WsConnection, err: string) =
      discard

    proc notifyClients() =
      {.gcsafe.}:
        writeWith changeLocker:
          hasChanges = false
        readWith changeLocker:
          for ws in wsClients:
            ws.sendText("1")

    proc getSlugHash(basePath, path: string): (string, string) =
      # Computes the slug and its secure hash for a given markdown file path
      var k = path.replace(basePath).replace(".md").slugify(allowSlash = true)
      if k == "index": k = "/"
      result = (k, $(secureHash(k)))

    proc isReservedLlmsFile(basePath, path: string): bool =
      ## Returns true for the reserved root `llms.md` (case-insensitive),
      ## e.g. `contents/llms.md`, `contents/LLMS.md`. Nested files such as
      ## `contents/docs/llms.md` (`/docs/llms`) are normal pages and return false.
      ## The reserved file only serves `/llms.txt` and must never create a
      ## `/llms` page route nor a search entry.
      try:
        if absolutePath(parentDir(path)) != absolutePath(basePath):
          return false
      except:
        if parentDir(path) != basePath:
          return false
      extractFilename(path).toLowerAscii() == "llms.md"

    proc purgeReservedLlms*(mdInstance: MarkdownInstance) =
      ## Removes a stale `/llms` page (from an older `booyaka.db`) so a
      ## reserved root `llms.md` can never resolve to a page route.
      if mdInstance.isNil or mdInstance.index.isNil or mdInstance.pages.isNil:
        return
      var staleKeys: seq[string] = @[]
      for slug in keys(mdInstance.index):
        if slug.strip(chars = {'/'}, leading = true, trailing = true).toLowerAscii() == "llms":
          staleKeys.add(slug)
      for slug in staleKeys:
        let hash = mdInstance.index[slug]
        mdInstance.index.del(slug)
        if mdInstance.pages.hasKey(hash):
          mdInstance.pages.del(hash)

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

    proc buildTocHtml(items: seq[tuple[level: int, anchor, title: string]]): string =
      # Builds a nested `<ul>`/`<li>` table of contents HTML from flat
      # heading items (in document order), nesting items based on their
      # heading level relative to the first (top-most) heading.
      if items.len == 0:
        return ""
      var stack: seq[int]
      for item in items:
        let level = item.level
        # close lists strictly deeper than the current level
        while stack.len > 0 and stack[^1] > level:
          discard stack.pop()
          if stack.len > 0:
            result.add("</li></ul>")
        if stack.len == 0:
          if result.len > 0:
            result.add("</li>")
          result.add("<li>")
          stack.add(level)
        elif stack[^1] == level:
          result.add("</li><li>")
        else:
          # opening a deeper nested list
          result.add("<ul><li>")
          stack.add(level)
        result.add("<a href=\"#" & item.anchor & "\">" & item.title & "</a>")
      # close any remaining open items/lists
      while stack.len > 0:
        result.add("</li>")
        discard stack.pop()
        if stack.len > 0:
          result.add("</ul>")

    proc parseMarkdownFile(mdInstance: MarkdownInstance, basePath,
                    path: string, hashedSlug: Option[(string, string)] = none((string, string)),
                    addToSearch: bool = true) = 
      # Parses a markdown file and updates the markdown instance
      # The reserved root `llms.md` only serves `/llms.txt` and must
      # never create a page route or search entry.
      if isReservedLlmsFile(basePath, path):
        return
      # Keep the module-level `contentPath` in sync so the `@<page>.md`
      # reference fallback can resolve files in the `build` path (which calls
      # this proc via `scanMarkdownFiles` instead of going through `init`).
      contentPath = basePath
      let rawContent = readFile(path)
      var md = newMarkdown(rawContent, markdownOptions)
      # script-safe JSON string of the raw markdown for the
      # "Copy as Markdown" share action (`<`/`>`/`&` are escaped
      # so the value can never break out of a `<script>` tag).
      # Tim Engine only accepts literal content inside `script` tags,
      # so the complete `<script type="application/json">` element is
      # pre-built here and injected into the template as raw HTML.
      let encodedMarkdown = $(newJString(rawContent))
      let
        # compute slug and hash
        slugHash =
          if not hashedSlug.isSome: getSlugHash(basePath, path)
          else: hashedSlug.get()
        # get previous and next navigation items
        (prev, next) = getPrevNext(globalBooyakaConfig.sidebar_navigation, slugHash[0])
        htmlContent: string = md.toHtml()   # convert markdown to HTML
        markdownSourceJson: string = encodedMarkdown
      
      # extract available metadata from the markdown file,
      # prioritizing YAML front matter if present
      let meta: JsonNode = toJson(md.getHeader()).fromJson()
      
      # add/update the search index with the new content
      if addToSearch and not searchInstance.isNil:
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

      # update the markdown instance index with the new slug and hash mapping
      mdInstance.index[slugHash[0]] = slugHash[1]

      # determine the section name for the current page based
      # on the sidebar navigation configuration
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
          tocHtml: buildTocHtml(md.getSelectorItems()),
          markdownSourceJson: markdownSourceJson,
          navigation: MarkdownPageBottomNavigation(previous: prev, next: next),
          lastEdited: some(now().toTime)
        )

      # write the parsed markdown content to disk
      # we write to a hashed filename to avoid issues with special
      # characters in URLs and to ensure uniqueness
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
      if isReservedLlmsFile(contentPath, path):
        # reserved root `llms.md` only serves `/llms.txt` (read from
        # disk per request); nothing to index and no page to re-render
        return
      gMarkdownService.parseMarkdownFile(contentPath, path)
      notifyClients()

    proc onDelete(file: watchout.File) =
      # Callback when a markdown file is deleted
      if isReservedLlmsFile(contentPath, file.getPath()):
        return
      echo "Markdown file deleted: ", file.getPath

    proc scanMarkdownFiles*(contentPath, dbPath, searchPath: string) =
      ## Scans the content directory for markdown files, parses them, and
      ## updates the markdown service index and search index accordingly.
      ## The reserved root `llms.md` (any case) is skipped: it only serves
      ## `/llms.txt` and must never create a `/llms` page or search entry.
      for path in walkDirRec(contentPath, {pcFile}):
        let fpath = path.splitFile
        if fpath.ext != ".md" or fpath.name.startsWith("!"):
          # skip non-markdown files and temporary files prefixed with "!"
          continue
        if isReservedLlmsFile(contentPath, path):
          continue
        let hashedSlug = getSlugHash(contentPath, path)
        if gMarkdownService.pages.hasKey(hashedSlug[1]):
          let md = gMarkdownService.pages[hashedSlug[1]]
          if md.lastEdited.isSome and md.lastEdited.get() >= getLastModificationTime(path):
            continue # skip unchanged files
        
        # parse markdown file and update the markdown service index
        gMarkdownService.parseMarkdownFile(contentPath, path, some(hashedSlug))
      
      # drop stale `/llms` entries from older dbs; root `llms.md`
      # is reserved for `/llms.txt` and must never resolve to a page
      gMarkdownService.purgeReservedLlms()
      if not searchInstance.isNil:
        searchInstance.purgeLlmsEntries()
      # write FBE-encoded caches (signature envelope included)
      writeDbFile(dbPath, encodeMarkdownInstance(gMarkdownService))
      writeDbFile(searchPath, encodeSpotlight(searchInstance[]))

    proc scanVersion*(projectPath, tag: string): MarkdownInstance =
      ## Extracts `tag` from the git repository at `projectPath`, scans its
      ## `contents` directory into a fresh MarkdownInstance (not added to the
      ## global search index) and registers it in `gMarkdownVersions`.
      let
        tagContentsPath = getTagContentsPath(projectPath, tag)
        instance = MarkdownInstance(
          pages: newTable[string, MarkdownPage](),
          index: newTable[string, string](),
          version: parseVersion(tag)
        )
      extractTag(projectPath, tag, getVersionsCachePath(projectPath) / tag)
      if not dirExists(tagContentsPath):
        return instance
      # `parseMarkdownFile` mutates the module-level `contentPath`; keep the
      # real one intact so the watchout watcher keeps working.
      let prevContentPath = contentPath
      contentPath = tagContentsPath
      for path in walkDirRec(tagContentsPath, {pcFile}):
        let fpath = path.splitFile
        if fpath.ext != ".md" or fpath.name.startsWith("!"):
          continue
        if isReservedLlmsFile(tagContentsPath, path):
          # reserved root `llms.md` only serves `/llms.txt`
          continue
        let hashedSlug = getSlugHash(tagContentsPath, path)
        instance.parseMarkdownFile(tagContentsPath, path, some(hashedSlug),
          addToSearch = false)
      contentPath = prevContentPath
      gMarkdownVersions[tag] = instance
      gVersionList.add(tag)
      result = instance

    proc initVersions*(projectPath: string) =
      ## Detects semver git tags in `projectPath` and scans each one into a
      ## versioned MarkdownInstance. No-op when versioning is disabled, the
      ## directory is not a git repository, or there are no semver tags.
      if not globalBooyakaConfig.git.enable_versioning:
        return
      if gMarkdownVersions.isNil:
        gMarkdownVersions = newTable[string, MarkdownInstance]()
      for tag in getSemverTags(projectPath):
        if gMarkdownVersions.hasKey(tag):
          continue
        discard scanVersion(projectPath, tag)

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

      # scan versioned documentation from git tags (when enabled)
      if booyakaProjectPath.len > 0:
        initVersions(booyakaProjectPath)
      
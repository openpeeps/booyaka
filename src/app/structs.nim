import std/[options, times, tables, strutils, os]
import pkg/openparser/[json, html]
import pkg/kapsis/interactive/prompts

type
  SidebarType* = enum
    ## enum representing the type of sidebar
    sidebarTypeNone = "none"
      ## No sidebar
    sidebarTypeNavigation = "navigation"
      ## Sidebar with navigation links defined in `sidebar_navigation` configuration
    sidebarTypeTableOfContents = "toc"
      ## Sidebar that automatically generates a table of contents based on page headings
  
  AppearanceDefaultTheme* = enum
    themeSystem = "system"
      ## Follow the user's OS theme preference
    themeLight = "light"
      ## Light theme mode
    themeDark = "dark"
      ## Dark theme mode

  MarkdownPageBottomNavigation* = object
    ## Represents the bottom navigation links for a Markdown page
    previous*: Option[BooyakaNavItem]
      ## Previous page navigation item
    next*: Option[BooyakaNavItem]
      ## Next page navigation item

  MarkdownPage* = object
    meta*: JsonNode
      ## Metadata for the Markdown page (e.g., title, description, etc.)
    title*: string
      ## The title of the page
    section*: string
      ## The section/category of the page
    content*: string
      ## The raw Markdown content of the page
    last_updated*: string
      ## The last updated timestamp of the page (formatted as a string)
    toc*: OrderedTableRef[string, string]
      ## Table of contents for the page (mapping section titles to anchors)
    toc_html*: string
      ## Pre-rendered nested table of contents HTML for the page
    markdown_source_json*: string
      ## Script-safe JSON-encoded raw Markdown source of the page,
      ## embedded in a `<script type="application/json">` tag for the
      ## "Copy as Markdown" share action
    navigation*: MarkdownPageBottomNavigation
      ## Navigation information for the page (previous/next links)
    last_edited*: Option[Time]
      ## The last edited time as a Time object (optional, can be used for sorting or display)

  BooyakaNavItem* = ref object
    ## Represents an item in the Booyaka navigation bar
    title*: string
      # The display title of the navigation item
    url*: string
      # The URL path the navigation item points to
    icon*: Option[string]
      # An optional icon associated with the navigation item
      # Represented as a string (e.g., icon class name or URL).
      # Booyaka is using Tabler Icons - https://tabler-icons.io/

  NavigationSection* = ref object
    ## Represents a section in the sidebar navigation
    name*: string
      ## The name of the navigation section
    items*: seq[BooyakaNavItem]
      ## A sequence of navigation items within the section

  BooyakaFooter* = object
    ## Represents the footer configuration for Booyaka
    text*: Option[string]
      ## Footer text content
    links*: Option[seq[BooyakaNavItem]]
      ## Footer links configuration
  
  BooyakaMetadata* = object
    ## Metadata information for the Booyaka site
    url*: string
      ## The public base URL of the documentation site, with or without a
      ## scheme: `"website.com"`, `"openpeeps.github.io/carne"` or
      ## `"https://openpeeps.github.io/carne"`.
      ## Required by `booyaka build`: the URL path becomes the prefix for
      ## every asset and page link so the static site also works from a
      ## subdirectory. Empty when unset (dev server ignores it).
    logo*: Option[string]
      ## URL or path to the logo image for the site
    logo_keep_gradient*: bool
      ## Whether to keep the original colors of the logo
      ## (if false, the logo will be styled to match the theme)
    title*: Option[string]
      ## The title of the site
    description*: Option[string]
      ## A short description of the site for SEO purposes
    keywords*: Option[seq[string]]
      ## A list of keywords for SEO purposes
  
  ContentSettings* = object
    ## Settings related to Markdown processing in Booyaka
    allowed_raw_html_tags*: Option[seq[HtmlTag]]
      ## A list of allowed raw HTML tags in Markdown content if
      ## not specified, only safe tags will be allowed (e.g.,
      ## "b", "i", "strong", "em", "a", "p", "ul", "ol", "li", etc.)
    show_last_updated*: bool
      ## Whether to show the "Last Updated" timestamp on pages
    last_date_updated_format*: string = "yyyy-MM-dd HH:mm:ss"
      ## The format string for displaying the "Last Updated" timestamp
    enable_auto_format_links*: bool = true
      ## Whether to automatically format URLs as clickable links in Markdown content
    bottom_navigation*: bool
      ## Whether to enable bottom navigation links on pages
    code_highlight_theme*: string = "default"
      ## Legacy client-side (highlight.js) theme name. Code blocks are now
      ## highlighted on the backend via SweetSyntax (`sweetsyntax.css`);
      ## this field is kept for config compatibility and currently ignored.
    code_line_numbers*: bool
      ## Whether to render line numbers alongside fenced code blocks
      ## (CSS counters, not copied to clipboard) (default: false)
    highlight_strip_lines*: bool = true
      ## Whether to strip leading/trailing blank lines from fenced
      ## code blocks before highlighting (default: true)
    share_ai_buttons*: bool = true
      ## Whether to show AI share buttons in the page header of documentation pages
    share_buttons_ai_providers*: Option[seq[ShareProvider]]
      ## A list of AI providers for share buttons (e.g.,
      ## "ChatGPT", "Claude", "DeepSeek", etc.)
    lazyload_iframes*: bool
      ## Whether to lazyload iframes in Markdown content by
      ## rewriting `src` to `data-src` (default: false)
    lazyload_videos*: bool
      ## Whether to lazyload videos and audio in Markdown content by
      ## rewriting `src` to `data-src` (default: false)
    lazyload_images*: bool
      ## Whether to lazyload images in Markdown content by
      ## rewriting `src` to `data-src` (default: false)
    page_references*: bool
      ## Whether to render `@<page>.md` references in Markdown content as
      ## rich page cards (default: false)
  
  SidebarSection* = object
    ## Represents a section in the sidebar
    title*: Option[string]
      ## The title of the sidebar section
    content*: Option[string]
      ## The content of the sidebar section (can be HTML or Markdown)

  BooyakaExtraSections* = object
    ## Extra sections for Booyaka configuration
    left_sidebar*: Option[seq[SidebarSection]]
      ## Extra sections for the left sidebar
    right_sidebar*: Option[seq[SidebarSection]]
      ## Extra sections for the right sidebar

  ShareProvider* = object
    ## Represents an AI share provider for share buttons
    label*: string
      ## The name of the AI provider (e.g., "ChatGPT", "Claude", etc.)
    url*: string
      ## The URL template for sharing content with the provider
    icon*: Option[string]
      ## An optional icon for the provider (e.g., icon class name or URL)
    description*: string
      ## A short description of the provider

  HeaderSearchSettings* = object
    ## Settings related to the search functionality in the header
    enable*: bool = true
      ## Whether to enable search functionality in the header
    index_meta_data*: bool = true
      ## Whether to index metadata for search
    index_page_titles*: bool = true
      ## Whether to index content for search
  
  HeaderSettings* = object
    ## General settings for Booyaka
    search*: HeaderSearchSettings
      ## Whether to enable search functionality
    notification*: Option[string]
      ## Optional HTML content for displaying a
      ## notification banner in the header (e.g., for announcements)
  
  AppearanceSettings* = object
    ## Appearance-related settings for Booyaka
    show_theme_switcher*: bool = true
      ## Whether to show a theme switcher (light/dark mode) in the header
    default_theme*: AppearanceDefaultTheme = AppearanceDefaultTheme.themeSystem
      ## The default theme for the site ("light", "dark", or "system") "system" will follow the user's OS preference
    show_toggle_left_sidebar*: bool = true
      ## Whether to show a toggle button for the left sidebar
    show_toggle_right_sidebar*: bool = false
      ## Whether to show a toggle button for the right sidebar
    background_noise_opacity*: float = 0.03
      ## Opacity of the background noise texture (0.0 to 1.0) Set to 0.0 to disable background noise

  ServerSettings* = object
    ## Supranim server settings for `booyaka start`. Projects created
    ## before this section existed fall back to these defaults.
    address*: string = "127.0.0.1"
      ## TCP bind address (`unix = true` turns it into a socket path)
    port*: int = 3000
      ## TCP port to listen on (overridden by `start --port`)
    threads*: int = 1
      ## Worker threads. 1 = single worker, 0 = one per CPU core
    unix*: bool = false
      ## Serve over a Unix domain socket instead of TCP (single-threaded)

  GitSettings* = object
    ## Git-related settings for Booyaka
    enable_versioning*: bool
      ## Whether to enable versioning based on Git tags/branches. When enabled, Booyaka
      ## will detect Git tags/branches and allow users to switch between different versions of the documentation site.
    enable_contributors_info*: bool
      ## Whether to show contributors information on pages based on Git commit history.
    latest_label*: string = "main"
      ## The label of the root version (the current working tree / default branch).
      ## Used by the version switcher and `versionPath` to detect the current version.

  BooyakaRoute* = object
    ## A custom route registered at `booyaka.config` level. Exactly one of
    ## `view` / `page` must be set:
    ## - `view`: a static Tim template, e.g. `"pages/contact"` renders
    ##   `themes/<theme>/views/pages/contact.timl`.
    ## - `page`: a Markdown file relative to `contents/`, e.g.
    ##   `"changelog.md"`. The file is served at `path` instead of its
    ##   natural slug (which is then excluded from the build).
    path*: string
      ## URL path of the route, e.g. `"/contact"`
    view*: Option[string]
      ## Tim view name for static template routes
    page*: Option[string]
      ## Markdown source for page routes, relative to `contents/`
    layout*: Option[string]
      ## Tim layout override (default `"base"`; Markdown frontmatter
      ## `layout:` wins over this)
    title*: Option[string]
      ## Meta title fallback for static view routes (no Markdown meta)
    description*: Option[string]
      ## Meta description fallback for static view routes

  BooyakaConfig* = object
    ## Configuration options for Booyaka This object is automatically populated from `booyaka.config.yaml` or `booyaka.config.json` file in the current directory.
    server*: ServerSettings
      ## Supranim server settings used by `booyaka start`
    theme*: string = "default"
      ## The active Tim theme, resolved from `<project>/themes/<name>`.
      ## Templates missing from the active theme fall back to the
      ## `default` theme shipped with Booyaka.
    metadata*: BooyakaMetadata
      ## Metadata information for the site
    appearance*: AppearanceSettings
      ## Appearance-related settings for Booyaka
    git*: GitSettings
      ## Git-related settings for Booyaka
    header*: HeaderSettings
      ## Header-related settings for Booyaka
    content*: ContentSettings
      ## Content-related settings for Booyaka
    navbar*: Option[seq[BooyakaNavItem]]
      ## Top navigation bar configuration
    sidebar_navigation*: seq[NavigationSection]
      ## Sidebar navigation configuration
    sidebar_left_type*: SidebarType
      ## Type of the left sidebar
    sidebar_right_type*: SidebarType
      ## Type of the right sidebar
    extra_sections*: BooyakaExtraSections
      ## Extra sections for future extensions
    footer*: BooyakaFooter
      ## Footer configuration
    routes*: seq[BooyakaRoute]
      ## Custom routes: static Tim views or Markdown pages served at
      ## explicit paths (see `BooyakaRoute`)

var
  enable_browser_sync* = true
    ## Whether to enable BrowserSync for live-reloading during
    ## writing documentation

  booyaka_project_path*: string

  global_booyaka_config*: BooyakaConfig
    ## Global variable to hold the Booyaka configuration loaded from the config file.
    ## This variable is accessible throughout the application and contains all the
    ## settings defined in `booyaka.config.yaml` or `booyaka.config.json`.
    ## 
    ## The configuration is loaded during the initialization of the
    ## application and can be used to customize the behavior and appearance
    ## of the documentation site.

proc ensureLeadingSlash*(config: BooyakaConfig) =
  ## Ensures that the given URL starts with a leading slash
  for section in config.sidebar_navigation:
    for navItem in section.items:
      if navItem.url.len > 0 and navItem.url[0] != '/':
        navItem.url.insert("/", 0)

proc routeSlug*(p: string): string =
  ## Slug form of a route path (`"/contact"` -> `"contact"`), matching the
  ## slug style of Markdown pages (no leading/trailing slashes).
  p.strip().strip(chars = {'/'}, leading = true, trailing = true)

proc routeViewName*(v: string): string =
  ## Normalizes a route `view` (or frontmatter `view:`) to a Tim dotted
  ## view name: `"pages/contact"` / `"pages/contact.timl"` -> `"pages.contact"`.
  var s = v.strip().replace("\\", "/")
  if s.endsWith(".timl"):
    s = s[0 .. ^6]
  s = s.strip(chars = {'/'}, leading = true, trailing = true)
  s.replace("/", ".")

proc findCustomRoute*(config: BooyakaConfig, path: string): Option[BooyakaRoute] =
  ## Returns the custom route registered for `path` (slash-tolerant), if any.
  let want = routeSlug(path)
  if want.len == 0:
    return none(BooyakaRoute)
  for r in config.routes:
    if routeSlug(r.path) == want:
      return some(r)
  none(BooyakaRoute)

proc validateRoutes*(config: var BooyakaConfig, projectPath: string) =
  ## Normalizes `routes` (paths, view names, page paths) and fails fast on
  ## invalid entries. Called from `loadBooyaka` so both `start` and `build`
  ## enforce the same rules. The homepage (`"/"`) and the reserved
  ## `/search`, `/results.json`, `/llms.txt`, `/assets` prefixes stay protected.
  var seen: seq[string] = @[]
  for i in 0 ..< config.routes.len:
    var r = config.routes[i]
    var p = r.path.strip().strip(chars = {'/'}, leading = true, trailing = true)
    r.path = "/" & p
    if p.len == 0:
      displayError("Invalid `routes[" & $i & "].path`: \"/\" is the homepage and cannot be overridden.",
        quitProcess = true)
    if r.path in ["/search", "/results.json", "/llms.txt", "/assets"] or
        r.path.startsWith("/assets/"):
      displayError("Invalid `routes[" & $i & "].path` \"" & r.path &
        "\": reserved by Booyaka.", quitProcess = true)
    let
      hasView = r.view.isSome and r.view.get.strip().len > 0
      hasPage = r.page.isSome and r.page.get.strip().len > 0
    if hasView == hasPage:
      displayError("Invalid route \"" & r.path &
        "\": set exactly one of `view` or `page`.", quitProcess = true)
    if p in seen:
      displayError("Duplicate route path \"" & r.path & "\".", quitProcess = true)
    seen.add(p)
    if hasView:
      r.view = some(routeViewName(r.view.get))
    if hasPage:
      var rel = r.page.get.strip().replace("\\", "/")
      rel = rel.strip(chars = {'/'}, leading = true, trailing = false)
      if rel.startsWith("contents/"):
        rel = rel["contents/".len .. ^1]
      if not rel.endsWith(".md"):
        displayError("Invalid route \"" & r.path &
          "\".page: must point to a `.md` file relative to `contents/`.",
          quitProcess = true)
      if not fileExists(projectPath / "contents" / rel):
        displayError("Invalid route \"" & r.path &
          "\".page: file not found: contents/" & rel, quitProcess = true)
      r.page = some(rel)
    if r.layout.isSome and r.layout.get.strip().len == 0:
      r.layout = none(string)
    elif r.layout.isSome:
      r.layout = some(r.layout.get.strip())
    config.routes[i] = r

proc siteBasePath*(config: BooyakaConfig): string =
  ## Path prefix derived from `metadata.url` for prefixing asset and page
  ## links in built output. Accepts bare hosts (`website.com`,
  ## `openpeeps.github.io/carne`) as well as full URLs
  ## (`https://openpeeps.github.io/carne`); both subpath forms return
  ## `"/carne"`, root-hosted sites return `""`. Never raises.
  var u = config.metadata.url.strip()
  if u.len == 0:
    return ""
  # drop `scheme://` when present
  let schemeIdx = u.find("://")
  if schemeIdx >= 0:
    u = u[schemeIdx + 3 .. ^1]
  # drop query/fragment
  let qIdx = u.find({'?', '#'})
  if qIdx >= 0:
    u = u[0 ..< qIdx]
  u = u.strip(chars = {'/'}, leading = false, trailing = true)
  if u.len == 0:
    return ""
  # the first segment is the host — unless there is only one segment,
  # in which case a dotted value is a bare host and anything else
  # (e.g. `carne`) is a subpath
  let slashIdx = u.find('/')
  var path: string
  if slashIdx < 0:
    if '.' in u or ':' in u:
      return ""
    path = u
  else:
    path = u[slashIdx .. ^1]
  if path.len == 0 or path == "/":
    return ""
  if path[0] != '/':
    path = "/" & path
  path
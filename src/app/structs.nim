import std/[options, json, times, tables]

type
  MarkdownPageBottomNavigation* = object
    previous*: Option[BooyakaNavItem]
      ## Previous page navigation item
    next*: Option[BooyakaNavItem]
      ## Next page navigation item

  MarkdownPage* = object
    meta*: JsonNode
    title*, section*: string
    content*: string
    last_updated*: string
    toc*: OrderedTableRef[string, string]
    navigation*: MarkdownPageBottomNavigation
    lastEdited*: Option[Time]

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
    text: Option[string]
      ## Footer text content
    links: Option[seq[BooyakaNavItem]]
      ## Footer links configuration

  SidebarType* = enum
    ## enum representing the type of sidebar
    SidebarTypeNone
    SidebarTypeNavigation
    SidebarTypeTableOfContents
  
  BooyakaMetadata* = object
    ## Metadata information for the Booyaka site
    url*: string
      ## The base URL of the documentation site
    title*: Option[string]
      ## The title of the site
    description*: Option[string]
      ## A short description of the site for SEO purposes
    keywords*: Option[seq[string]]
      ## A list of keywords for SEO purposes
  
  ContentSettings* = object
    ## Settings related to Markdown processing in Booyaka
    allowedRawHtmlTags*: Option[seq[string]]
      ## A list of allowed raw HTML tags in Markdown content
      ## If not specified, only safe tags will be allowed
      ## (e.g., "b", "i", "strong", "em", "a", "p", "ul", "ol", "li", etc.)
    showLastUpdated*: bool
      ## Whether to show the "Last Updated" timestamp on pages
    lastDateUpdatedFormat*: string = "yyyy-MM-dd HH:mm:ss"
      ## The format string for displaying the "Last Updated" timestamp
    enableAutoFormatLinks*: bool = true
      ## Whether to automatically format URLs as clickable
      ## links in Markdown content
    bottom_navigation*: bool
      ## Whether to enable bottom navigation links on pages
    codeHighlightTheme*: string = "default"
      ## The code syntax highlighting theme to use
      ## (e.g., "default", "dark", "funky", "okaidia", etc.)
    share_ai_buttons*: bool = true
      ## Whether to show AI share buttons in the page header of documentation pages
    share_buttons_ai_providers*: Option[seq[ShareProvider]]
      ## A list of AI providers for share buttons (e.g., "ChatGPT", "Claude", "DeepSeek", etc.)
  
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
  
  AppearanceDefaultTheme* = enum
    System = "system"
    Light = "light"
    Dark = "dark"
  
  AppearanceSettings* = object
    ## Appearance-related settings for Booyaka
    show_theme_switcher*: bool = true
      ## Whether to show a theme switcher (light/dark mode) in the header
    defaullt_theme*: AppearanceDefaultTheme = AppearanceDefaultTheme.System
      ## The default theme for the site ("light", "dark", or "system")
      ## "system" will follow the user's OS preference
    show_toggle_left_sidebar*: bool = true
      ## Whether to show a toggle button for the left sidebar
    show_toggle_right_sidebar*: bool = false
      ## Whether to show a toggle button for the right sidebar
    container_width*: string = "col-lg-10 mx-auto"
      ## Bootstrap 5 container width class for the main content area
    content_width*: string = "col-lg-7"
      ## Bootstrap 5 column width class for the content area
    background_noise_opacity*: float = 0.03
      ## Opacity of the background noise texture (0.0 to 1.0)
      ## Set to 0.0 to disable background noise

  GitSettings* = object
    ## Git-related settings for Booyaka
    enable_versioning*: bool
      ## Whether to enable versioning based on Git tags/branches.
      ## When enabled, Booyaka will detect Git tags/branches
      ## and allow users to switch between different versions
      ## of the documentation site.
    enable_contributors_info*: bool
      ## Whether to show contributors information on pages
      ## based on Git commit history.

  BooyakaConfig* = object
    ## Configuration options for Booyaka
    ## This object is automatically populated from `booyaka.config.yaml`
    ## or `booyaka.config.json` file in the current directory.
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
    sidebarLeftType*: SidebarType
      ## Type of the left sidebar
    sidebarRightType*: SidebarType
      ## Type of the right sidebar
    extra_sections*: BooyakaExtraSections
      ## Extra sections for future extensions
    footer: BooyakaFooter

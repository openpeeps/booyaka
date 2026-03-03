import std/[options, json, times, tables]
import pkg/jsony

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
    navigation*: MarkdownPageBottomNavigation
      ## Navigation information for the page (previous/next links)
    lastEdited*: Option[Time]
      ## The last edited time as a Time object (optional, can be used for sorting or display)

  BooyakaNavItem* = ref object
    ## Represents an item in the Booyaka navigation bar
    title*: string
      # The display title of the navigation item
    url*: string
      # The URL path the navigation item points to
    icon*: Option[string]
      # An optional icon associated with the navigation item Represented as a string (e.g., icon class name or URL). Booyaka is using Tabler Icons - https://tabler-icons.io/

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
  
  BooyakaMetadata* = object
    ## Metadata information for the Booyaka site
    url*: string
      ## The base URL of the documentation site
    logo*: Option[string]
      ## URL or path to the logo image for the site
    title*: Option[string]
      ## The title of the site
    description*: Option[string]
      ## A short description of the site for SEO purposes
    keywords*: Option[seq[string]]
      ## A list of keywords for SEO purposes
  
  ContentSettings* = object
    ## Settings related to Markdown processing in Booyaka
    allowedRawHtmlTags*: Option[seq[string]]
      ## A list of allowed raw HTML tags in Markdown content if not specified, only safe tags will be allowed (e.g., "b", "i", "strong", "em", "a", "p", "ul", "ol", "li", etc.)
    showLastUpdated*: bool
      ## Whether to show the "Last Updated" timestamp on pages
    lastDateUpdatedFormat*: string = "yyyy-MM-dd HH:mm:ss"
      ## The format string for displaying the "Last Updated" timestamp
    enableAutoFormatLinks*: bool = true
      ## Whether to automatically format URLs as clickable links in Markdown content
    bottom_navigation*: bool
      ## Whether to enable bottom navigation links on pages
    codeHighlightTheme*: string = "default"
      ## The code syntax highlighting theme to use (e.g., "default", "dark", "funky", "okaidia", etc.)
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
    container_width*: string = "col-lg-10 mx-auto"
      ## Bootstrap 5 container width class for the main content area
    content_width*: string = "col-lg-7"
      ## Bootstrap 5 column width class for the content area
    background_noise_opacity*: float = 0.03
      ## Opacity of the background noise texture (0.0 to 1.0) Set to 0.0 to disable background noise

  GitSettings* = object
    ## Git-related settings for Booyaka
    enable_versioning*: bool
      ## Whether to enable versioning based on Git tags/branches. When enabled, Booyaka
      ## will detect Git tags/branches and allow users to switch between different versions of the documentation site.
    enable_contributors_info*: bool
      ## Whether to show contributors information on pages based on Git commit history.

  BooyakaConfig* = object
    ## Configuration options for Booyaka This object is automatically populated from `booyaka.config.yaml` or `booyaka.config.json` file in the current directory.
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
      ## Footer configuration

var
  booyakaProjectPath*: string
  globalBooyakaConfig*: BooyakaConfig
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
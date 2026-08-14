# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

import std/json
import std/[strutils, os]
import pkg/supranim/[controller, core/paths]

import ../service/provider/[tim, markdown, search]
import ../app/structs

proc isSPARequest(req: var Request): bool =
  # A simple heuristic to determine if the request is an AJAX request
  # You can customize this based on your frontend framework's conventions
  req.getHeaders().isSome and req.getHeaders().get().hasKey("X-Requested-With")

proc versionPath(label: string): string =
  ## Returns the URL prefix for a documentation version.
  ## The root version (working tree / main) has no prefix.
  if label.len == 0 or label == globalBooyakaConfig.git.latest_label:
    return ""
  "/" & label

proc versionsData(currentSlug = ""): JsonNode =
  ## Builds the version switcher data: `main` (root) plus every loaded tag.
  ## When `currentSlug` is given, each entry links to the same page in that
  ## version when it exists, otherwise it falls back to the version index.
  var versions = newJArray()
  let items = @[globalBooyakaConfig.git.latest_label] & gVersionList
  for label in items:
    var target = versionPath(label)
    if currentSlug.len > 0 and currentSlug != "/":
      let slugPath = currentSlug.strip(chars = {'/'}, leading = true)
      let hasPage =
        if label == globalBooyakaConfig.git.latest_label:
          gMarkdownService.index.hasKey(currentSlug)
        else:
          not gMarkdownVersions.isNil and gMarkdownVersions.hasKey(label) and
            gMarkdownVersions[label].index.hasKey(currentSlug)
      if hasPage:
        target = versionPath(label) & "/" & slugPath
    versions.add(%*{
      "label": label,
      "path": target
    })
  %*{
    "enable": globalBooyakaConfig.git.enable_versioning,
    "items": versions
  }

proc versionPage(mdInstance: MarkdownInstance, slug: string): JsonNode =
  ## Resolves `slug` within the given MarkdownInstance, returning the
  ## rendered page data or `nil` when the slug is not found.
  if mdInstance.index.hasKey(slug):
    return toJson(mdInstance.pages[mdInstance.index[slug]]).fromJson()
  nil

ctrl getHomepage:
  ## renders the home page
  let markdownPage = gMarkdownService.pages[gMarkdownService.index["/"]]
  render("index", local = &*{
    "markdown": markdownPage,
    "config": toJson(globalBooyakaConfig).fromJson(),
    "version": {
      "label": "",
      "path": ""
    },
    "versions": versionsData("/")
  })

ctrl getResultsJson:
  ## returns search results as JSON
  json(%*{
    "results": spotlight().getEntries()
  })

ctrl getLlmsTxt:
  ## serves the raw `llms.md` file (when present in the root of the
  ## contents directory) at `/llms.txt` as plain text.
  {.gcsafe.}:
    let llmsPath = booyakaProjectPath / "contents" / "llms.md"
    if fileExists(llmsPath):
      respond(readFile(llmsPath), "text/plain; charset=utf-8")
    else:
      respond(Http404, "Not Found", "text/plain; charset=utf-8")

ctrl getSearch:
  ## renders the search results page.
  ## The rendering of the search results is done at client side
  ## using JavaScript, which fetches the search results from the
  ## getResultsJson endpoint.
  render("search", local = &*{
    "config": toJson(globalBooyakaConfig).fromJson(),
    "versions": versionsData()
  })

ctrl getVersionSlug:
  {.gcsafe.}:
    let
      label = req.params["version"]
      slug = req.params["slug"]
    if gMarkdownVersions.isNil or not gMarkdownVersions.hasKey(label):
      render("errors.4xx", local = &*{
        "markdown": {
          "meta": {
            "title": "Version Not Found",
            "description": "The documentation version you are looking for does not exist."
          },
        },
        "config": toJson(globalBooyakaConfig).fromJson()
      }, httpCode = Http404)
    else:
      let page = versionPage(gMarkdownVersions[label], slug)
      if page.isNil:
        render("errors.4xx", local = &*{
          "markdown": {
            "meta": {
              "title": "Page Not Found",
              "description": "The page you are looking for does not exist."
            },
          },
          "config": toJson(globalBooyakaConfig).fromJson()
        }, httpCode = Http404)
      else:
        if req.isSPARequest:
          renderView("index", local = &*{
            "markdown": page,
            "config": toJson(globalBooyakaConfig).fromJson(),
            "version": {
              "label": label,
              "path": versionPath(label)
            },
            "versions": versionsData(slug)
          })
        else:
          render("index", local = &*{
            "markdown": page,
            "config": toJson(globalBooyakaConfig).fromJson(),
            "version": {
              "label": label,
              "path": versionPath(label)
            },
            "versions": versionsData(slug)
          })

ctrl getVersion:
  {.gcsafe.}:
    let label = req.params["version"]
    if gMarkdownVersions.isNil or not gMarkdownVersions.hasKey(label):
      render("errors.4xx", local = &*{
        "markdown": {
          "meta": {
            "title": "Version Not Found",
            "description": "The documentation version you are looking for does not exist."
          },
        },
        "config": toJson(globalBooyakaConfig).fromJson()
      }, httpCode = Http404)
    else:
      let mdInstance = gMarkdownVersions[label]
      let page = versionPage(mdInstance, "/")
      if page.isNil:
        render("errors.4xx", local = &*{
          "markdown": {
            "meta": {
              "title": "Page Not Found",
              "description": "The page you are looking for does not exist."
            },
          },
          "config": toJson(globalBooyakaConfig).fromJson()
        }, httpCode = Http404)
      else:
        render("index", local = &*{
          "markdown": page,
          "config": toJson(globalBooyakaConfig).fromJson(),
          "version": {
            "label": label,
            "path": versionPath(label)
          },
          "versions": versionsData("/")
        })

ctrl getSlug:
  {.gcsafe.}:
    let slug = req.params["slug"]
    if gMarkdownService.index.hasKey(slug):
      if req.isSPARequest:
        renderView("index", local = &*{
          "markdown": gMarkdownService.pages[gMarkdownService.index[slug]],
          "config": toJson(globalBooyakaConfig).fromJson(),
          "version": {
            "label": "",
            "path": ""
          },
          "versions": versionsData(slug)
        })
      else:
        render("index", local = &*{
          "markdown": gMarkdownService.pages[gMarkdownService.index[slug]],
          "config": toJson(globalBooyakaConfig).fromJson(),
          "version": {
            "label": "",
            "path": ""
          },
          "versions": versionsData(slug)
        })
    else:
      render("errors.4xx", local = &*{
        "markdown": {
          "meta": {
            "title": "Page Not Found",
            "description": "The page you are looking for does not exist."
          },
        },
        "config": toJson(globalBooyakaConfig).fromJson()
      }, httpCode = Http404)

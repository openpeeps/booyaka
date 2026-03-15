# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

import std/json
import pkg/supranim/[controller, core/paths]

import ../service/provider/[tim, markdown, search]
import ../app/structs

proc isSPARequest(req: var Request): bool =
  # A simple heuristic to determine if the request is an AJAX request
  # You can customize this based on your frontend framework's conventions
  req.getHeaders().isSome and req.getHeaders().get().hasKey("X-Requested-With")

ctrl getHomepage:
  ## renders the home page
  let markdownPage = gMarkdownService.pages[gMarkdownService.index["/"]]
  render("index", local = &*{
    "markdown": markdownPage,
    "config": toJson(globalBooyakaConfig).fromJson()
  })

ctrl getResultsJson:
  ## returns search results as JSON
  json(%*{
    "results": spotlight().getEntries()
  })

ctrl getSearch:
  ## renders the search results page.
  ## The rendering of the search results is done at client side
  ## using JavaScript, which fetches the search results from the
  ## getResultsJson endpoint.
  # let query = request.query["q"] or ""
  # let results = spotlight().search(query)
  render("search", local = &*{
    # "query": query,
    # "results": results,
    "config": toJson(globalBooyakaConfig).fromJson()
  })

ctrl getSlug:
  {.gcsafe.}:
    let slug = req.params["slug"]
    if gMarkdownService.index.hasKey(slug):
      if req.isSPARequest:
        renderView("index", local = &*{
          "markdown": gMarkdownService.pages[gMarkdownService.index[slug]],
          "config": toJson(globalBooyakaConfig).fromJson()
        })
      else:
        render("index", local = &*{
          "markdown": gMarkdownService.pages[gMarkdownService.index[slug]],
          "config": toJson(globalBooyakaConfig).fromJson()
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
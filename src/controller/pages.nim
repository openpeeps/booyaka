# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

import std/[os, json, tables, sequtils]

import pkg/[bag, enimsql]
import pkg/supranim/[core/paths, controller]
import ../service/provider/[db, session, tim, markdown, search]

import ../app/structs

ctrl getHomepage:
  ## renders the home page
  let markdownPage = globalMarkdownService.pages[globalMarkdownService.index["/"]]
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
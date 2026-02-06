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
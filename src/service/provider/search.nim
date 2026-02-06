# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

import std/[strutils, tables, json, times, options, os]

import pkg/[jsony, flatty, supersnappy]
import pkg/supranim/core/[application, servicemanager, paths]

initService Spotlight[Singleton]:
  backend do:
    type
      Entry = object
        url*: string
          ## URL of the entry
        title*: string
          ## Title of the entry
        description*: Option[string]
          ## Short description of the entry
        headings*: Option[seq[string]]
          ## Optional list of headings within the entry
          ## to improve search granularity

      Spotlight* = object
        entries: seq[Entry]
          ## Table of search entries indexed by URL
        index*: TableRef[string, int]
          ## A table for indexing entries
      
      SpotlightInstance* = ptr Spotlight
  
  client do:
    proc init*(app: Application) =
      ## Initialize the Spotlight singleton service
      let booyakaSearchPath = app.applicationPaths.getInstallationPath / "booyaka.search.db"
      let spotlight = getSpotlightInstance(
        proc(instance: SpotlightInstance) = 
          if fileExists(booyakaSearchPath):
            instance[] = fromFlatty(uncompress(readFile(booyakaSearchPath)), Spotlight)
          else:
            instance.index = newTable[string, int]()
      )

    proc spotlight*(): SpotlightInstance {.inline.} =
      ## Retrieve the Spotlight singleton instance
      getSpotlightInstance()

    proc addEntry*(spotlight: SpotlightInstance, key, url, title: string,
                    description: Option[string] = none(string),
                    headings: Option[seq[string]] = none(seq[string])) =
      ## Add a new entry to the Spotlight search index
      if spotlight.index.contains(key):
        return # entry already exists
      spotlight.index[key] = spotlight.entries.len
      spotlight.entries.add(Entry(url: url, title: title,
              description: description,
              headings: headings))
    
    proc getEntries*(spotlight: SpotlightInstance): seq[Entry] =
      ## Retrieve all entries in the Spotlight search index
      return spotlight.entries
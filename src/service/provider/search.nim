# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

## This module implements the Spotlight search provider service for Booyaka.
## 
## It defines a Spotlight service that maintains a search index of documentation entries,
## allowing for efficient search and retrieval of content based on URLs, titles, descriptions, and headings
## 
## The service provides methods to add new entries to the search index and retrieve all indexed entries.
## The search index is stored in a flat file database for persistence across application restarts.

import std/[strutils, tables, times, options, os]
import pkg/openparser/fbe
import pkg/supranim/core/[application, services, paths]
import ./dbcodec

initService Spotlight[Singleton]:
  backend do:
    type
      Entry = object
        key*: string
          ## Hash key of the entry (slug hash)
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
    proc writeEntryFields(b: var Buffer, e: Entry) =
      b.writeField(1'u16, proc (bb: var Buffer) = bb.writeString(e.key))
      b.writeField(2'u16, proc (bb: var Buffer) = bb.writeString(e.url))
      b.writeField(3'u16, proc (bb: var Buffer) = bb.writeString(e.title))
      b.writeField(4'u16, proc (bb: var Buffer) = bb.writeOptString(e.description))
      b.writeField(5'u16, proc (bb: var Buffer) = bb.writeOptStrSeq(e.headings))

    proc handleEntryField(fid: uint16, fsz: int, b: var Buffer, into: var Entry) =
      case fid
      of 1'u16: into.key = b.readString()
      of 2'u16: into.url = b.readString()
      of 3'u16: into.title = b.readString()
      of 4'u16: into.description = b.readOptString()
      of 5'u16: into.headings = b.readOptStrSeq()
      else: discard

    proc writeEntry(b: var Buffer, e: Entry) =
      b.beginInnerStruct(DbCodecVersion)
      writeEntryFields(b, e)
      b.endInnerStruct()

    proc readEntry(b: var Buffer): Entry =
      var outVer: uint32
      b.decodeInnerInto(result, handleEntryField, outVer)

    proc writeSpotlightFields(b: var Buffer, s: Spotlight) =
      b.writeField(1'u16, proc (bb: var Buffer) =
        writeVector[Entry](bb, s.entries,
          proc (bbb: var Buffer, e: Entry) = bbb.writeEntry(e)))
      b.writeField(2'u16, proc (bb: var Buffer) = bb.writeStrIntMap(s.index))

    proc handleSpotlightField(fid: uint16, fsz: int, b: var Buffer,
                              into: var Spotlight) =
      case fid
      of 1'u16:
        into.entries = readVector[Entry](b, 
          proc (bb: var Buffer): Entry = bb.readEntry())
      of 2'u16:
        into.index = b.readStrIntMap()
      else: discard

    proc encodeSpotlight*(s: Spotlight): Buffer =
      ## Serializes a `Spotlight` value into an FBE payload buffer
      ## (wrap with `writeDbFile` for the signature envelope)
      result = initBuffer()
      encodeRootFrom(result, s, writeSpotlightFields, DbCodecVersion)

    proc decodeSpotlight*(b: var Buffer): Spotlight =
      ## Deserializes a `Spotlight` value from an FBE payload buffer
      ## (unwrap with `readDbFile` first)
      result.entries = @[]
      result.index = newTable[string, int]()
      var outVer: uint32
      b.decodeRootInto(result, handleSpotlightField, outVer)

    proc removeEntry*(spotlight: SpotlightInstance, key: string) =
      ## Removes an entry by its hash key, rebuilding positions
      if spotlight.isNil or spotlight.index.isNil or not spotlight.index.contains(key):
        return
      let pos = spotlight.index[key]
      if pos < 0 or pos >= spotlight.entries.len:
        spotlight.index.del(key)
        return
      spotlight.entries.delete(pos)
      spotlight.index.clear()
      for i, entry in spotlight.entries:
        spotlight.index[entry.key] = i

    proc purgeLlmsEntries*(spotlight: SpotlightInstance) =
      ## Drops any search entries pointing at the reserved `/llms` slug
      ## (case-insensitive). Used because root `llms.md` is reserved for
      ## `/llms.txt` and must never be indexed or searchable.
      if spotlight.isNil:
        return
      var kept = newSeq[Entry]()
      for entry in spotlight.entries:
        # legacy entries may predate the `key` field; fall back to url check
        if entry.url.strip(chars = {'/'}, leading = true, trailing = true).toLowerAscii() != "llms":
          kept.add(entry)
      if kept.len != spotlight.entries.len:
        spotlight.entries = kept
        if spotlight.index.isNil:
          spotlight.index = newTable[string, int]()
        else:
          spotlight.index.clear()
        for i, entry in spotlight.entries:
          if entry.key.len > 0:
            spotlight.index[entry.key] = i
          else:
            spotlight.index[entry.url] = i

    proc loadCachedSpotlight(path: string): tuple[ok: bool, val: Spotlight] =
      ## Decodes a previously written `booyaka.search.db`. Returns
      ## `ok=false` for missing, stale or corrupt files; the caller then
      ## starts fresh and the markdown scan rebuilds the index.
      ## NOTE: this runs *outside* the instance callback below because
      ## FBE's callback-based decode performs indirect calls which cannot
      ## be proven GC-safe (see `GcUnsafe2` in `openparser/fbe`).
      var payload: Buffer
      if readDbFile(path, payload) != dbOk:
        return (false, Spotlight(entries: @[], index: newTable[string, int]()))
      try:
        (true, decodeSpotlight(payload))
      except CatchableError:
        (false, Spotlight(entries: @[], index: newTable[string, int]()))

    proc init*(app: Application) =
      ## Initialize the Spotlight singleton service
      let booyakaSearchPath = app.applicationPaths.getInstallationPath / "booyaka.search.db"
      let cached = loadCachedSpotlight(booyakaSearchPath)
      let spotlight = getSpotlightInstance(
        proc(instance: SpotlightInstance) =
          if cached.ok:
            instance[] = cached.val
          else:
            # missing file (first run) or stale/foreign format
            # (pre-FBE flatty db, codec or Booyaka version mismatch):
            # start fresh, the markdown scan rebuilds the index
            instance.entries = @[]
            instance.index = newTable[string, int]()
          if instance.index.isNil:
            instance.index = newTable[string, int]()
          # root `llms.md` is reserved for `/llms.txt`; never searchable
          instance.purgeLlmsEntries()
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
      spotlight.entries.add(Entry(key: key, url: url, title: title,
              description: description,
              headings: headings))
     
    proc getEntries*(spotlight: SpotlightInstance): seq[Entry] =
      ## Retrieve all entries in the Spotlight search index
      return spotlight.entries
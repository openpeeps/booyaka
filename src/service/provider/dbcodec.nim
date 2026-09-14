# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

## Custom FBE binary codecs for the on-disk caches (`booyaka.db` and
## `booyaka.search.db`), built on `pkg/openparser/fbe`.
##
## FBE's high-level `encode` only supports plain scalars, so every
## composite Booyaka type (tables, options, `Time`, `JsonNode`, ref
## objects, enums) gets an explicit field-id codec below. Field ids are
## stable; unknown ids are skipped on decode, so newer writers stay
## forward compatible with older readers.
##
## Every `.db` file is wrapped in a small signature envelope
## (see `writeDbFile` / `readDbFile`):
##   magic "BOOYAKA1" | codec version (u32) | booyaka version (string)
##   | payload length (u32) | FBE payload bytes
## A magic or version mismatch means the file is stale or foreign, and
## the caller must rebuild from scratch via rescan (the DBs are caches).

import std/[options, times, tables, sequtils]
import pkg/semver
import pkg/openparser/[fbe, json, html]
import ../../app/structs

export fbe.Buffer, fbe.initBuffer

const
  DbMagic* = "BOOYAKA1"
    ## File signature written at the start of every `.db` file
  DbCodecVersion*: uint32 = 1
    ## Version of the codec layout below. Bump when field ids or the
    ## envelope format change in an incompatible way.
  BooyakaDbVersion* = "0.2.0"
    ## Booyaka release that wrote the file. Must match the `version`
    ## in `booyaka.nimble`; a mismatch invalidates the cache.
    ## Keep in sync manually when releasing.

type
  DbReadStatus* = enum
    ## Outcome of `readDbFile`
    dbOk                ## valid envelope, payload ready in `payload`
    dbMissing           ## file does not exist (first run)
    dbInvalid           ## unreadable envelope or corrupt payload framing
    dbCodecMismatch     ## written by an incompatible codec version
    dbVersionMismatch   ## written by a different Booyaka release

# ---------------------------------------------------------------------------
# Buffer <-> file helpers
# ---------------------------------------------------------------------------

proc bufferToString*(b: Buffer): string =
  ## Copies raw buffer bytes into a string for `writeFile`
  let n = b.data.len
  result = newStringOfCap(n)
  result.setLen(n)
  if n > 0:
    copyMem(cast[ptr uint8](addr result[0]), unsafeAddr b.data[0], n)

proc stringToBuffer*(s: string): Buffer =
  ## Wraps file bytes into a fresh read buffer (`pos = 0`)
  let n = s.len
  result.data = newSeq[uint8](n)
  if n > 0:
    copyMem(addr result.data[0], cast[ptr uint8](unsafeAddr s[0]), n)
  result.pos = 0

# ---------------------------------------------------------------------------
# Signature envelope
# ---------------------------------------------------------------------------

proc writeDbFile*(path: string, payload: Buffer) =
  ## Writes `payload` to `path` wrapped in the signature envelope
  var b = initBuffer(payload.data.len + 64)
  b.writeString(DbMagic)
  b.writeUint32LE(DbCodecVersion)
  b.writeString(BooyakaDbVersion)
  b.writeBytes(payload.data)
  writeFile(path, bufferToString(b))

proc readDbFile*(path: string, payload: var Buffer): DbReadStatus =
  ## Reads `path`, validates the signature envelope and returns the raw
  ## FBE payload in `payload` (`pos = 0`). Anything but `dbOk` means the
  ## caller must rebuild the cache from scratch.
  var s: string
  try:
    s = readFile(path)
  except IOError:
    return dbMissing
  except CatchableError:
    return dbInvalid
  var b = stringToBuffer(s)
  try:
    if b.readString() != DbMagic:
      return dbInvalid
    if b.readUint32LE() != DbCodecVersion:
      return dbCodecMismatch
    if b.readString() != BooyakaDbVersion:
      return dbVersionMismatch
    payload = stringToBuffer(cast[string](b.readBytes()))
  except CatchableError:
    return dbInvalid
  dbOk

# ---------------------------------------------------------------------------
# Primitive codecs (unsupported by FBE's high-level `encode`)
# ---------------------------------------------------------------------------

proc writeOptString*(b: var Buffer, v: Option[string]) =
  let s = v.get("")
  writeOptional[string](b, v.isSome, s,
    proc (bb: var Buffer, x: string) = bb.writeString(x))

proc readOptString*(b: var Buffer): Option[string] =
  var has = false
  let s = readOptional[string](b, 
    proc (bb: var Buffer): string = bb.readString(), has)
  if has: some(s) else: none(string)

proc writeOptStrSeq*(b: var Buffer, v: Option[seq[string]]) =
  let items = v.get(@[])
  writeOptional[seq[string]](b, v.isSome, items,
    proc (bb: var Buffer, xs: seq[string]) =
      writeVector[string](bb, xs,
        proc (bbb: var Buffer, x: string) = bbb.writeString(x)))

proc readOptStrSeq*(b: var Buffer): Option[seq[string]] =
  var has = false
  let items = readOptional[seq[string]](b, 
    proc (bb: var Buffer): seq[string] =
      readVector[string](bb,
        proc (bbb: var Buffer): string = bbb.readString()), has)
  if has: some(items) else: none(seq[string])

proc writeUnixTime*(b: var Buffer, t: Time) =
  b.writeInt64LE(t.toUnix())

proc readUnixTime*(b: var Buffer): Time =
  b.readInt64LE().fromUnix()

proc writeOptTime*(b: var Buffer, v: Option[Time]) =
  let t = v.get(fromUnix(0))
  writeOptional[Time](b, v.isSome, t,
    proc (bb: var Buffer, x: Time) = bb.writeUnixTime(x))

proc readOptTime*(b: var Buffer): Option[Time] =
  var has = false
  let t = readOptional[Time](b, 
    proc (bb: var Buffer): Time = bb.readUnixTime(), has)
  if has: some(t) else: none(Time)

proc writeJsonNode*(b: var Buffer, n: JsonNode) =
  ## `JsonNode` round-trips through its JSON text (`nil` <-> "")
  if n.isNil:
    b.writeString("")
  else:
    b.writeString(toJson(n))

proc readJsonNode*(b: var Buffer): JsonNode =
  let s = b.readString()
  if s.len == 0:
    return nil
  try:
    fromJson(s)
  except CatchableError:
    nil

proc writeStrMap*(b: var Buffer, t: TableRef[string, string]) =
  let items =
    if t.isNil: newSeq[tuple[key: string, val: string]]()
    else: toSeq(pairs(t))
  writeMap[string, string](b, items,
    proc (bb: var Buffer, k: string) = bb.writeString(k),
    proc (bb: var Buffer, v: string) = bb.writeString(v))

proc readStrMap*(b: var Buffer): TableRef[string, string] =
  result = newTable[string, string]()
  for kv in readMap[string, string](b, 
      proc (bb: var Buffer): string = bb.readString(),
      proc (bb: var Buffer): string = bb.readString()):
    result[kv.key] = kv.val

proc writeStrIntMap*(b: var Buffer, t: TableRef[string, int]) =
  let items =
    if t.isNil: newSeq[tuple[key: string, val: int]]()
    else: toSeq(pairs(t))
  writeMap[string, int32](b, items.mapIt((key: it.key, val: int32(it.val))),
    proc (bb: var Buffer, k: string) = bb.writeString(k),
    proc (bb: var Buffer, v: int32) = bb.writeInt32LE(v))

proc readStrIntMap*(b: var Buffer): TableRef[string, int] =
  result = newTable[string, int]()
  for kv in readMap[string, int32](b, 
      proc (bb: var Buffer): string = bb.readString(),
      proc (bb: var Buffer): int32 = bb.readInt32LE()):
    result[kv.key] = int(kv.val)

proc writeOrderedStrMap*(b: var Buffer, t: OrderedTableRef[string, string]) =
  let items =
    if t.isNil: newSeq[tuple[key: string, val: string]]()
    else: toSeq(pairs(t))
  writeMap[string, string](b, items,
    proc (bb: var Buffer, k: string) = bb.writeString(k),
    proc (bb: var Buffer, v: string) = bb.writeString(v))

proc readOrderedStrMap*(b: var Buffer): OrderedTableRef[string, string] =
  result = newOrderedTable[string, string]()
  for kv in readMap[string, string](b, 
      proc (bb: var Buffer): string = bb.readString(),
      proc (bb: var Buffer): string = bb.readString()):
    result[kv.key] = kv.val

# ---------------------------------------------------------------------------
# semver.Version
# ---------------------------------------------------------------------------

proc writeSemverVersion*(b: var Buffer, v: semver.Version) =
  b.beginInnerStruct(DbCodecVersion)
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeInt32LE(int32(v.major)))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeInt32LE(int32(v.minor)))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeInt32LE(int32(v.patch)))
  b.writeField(4'u16, proc (bb: var Buffer) = bb.writeString(v.build))
  b.writeField(5'u16, proc (bb: var Buffer) = bb.writeString(v.metadata))
  b.endInnerStruct()

proc handleSemverVersionField(fid: uint16, fsz: int, b: var Buffer,
                              into: var semver.Version) =
  case fid
  of 1'u16: into.major = int(b.readInt32LE())
  of 2'u16: into.minor = int(b.readInt32LE())
  of 3'u16: into.patch = int(b.readInt32LE())
  of 4'u16: into.build = b.readString()
  of 5'u16: into.metadata = b.readString()
  else: discard

proc readSemverVersion*(b: var Buffer): semver.Version =
  var outVer: uint32
  b.decodeInnerInto(result, handleSemverVersionField, outVer)

# ---------------------------------------------------------------------------
# Navigation items / sections (ref objects; nil-safe)
# ---------------------------------------------------------------------------

proc writeNavItemFields(b: var Buffer, item: BooyakaNavItem) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeString(item.title))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeString(item.url))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeOptString(item.icon))

proc handleNavItemField(fid: uint16, fsz: int, b: var Buffer,
                        into: var BooyakaNavItem) =
  case fid
  of 1'u16: into.title = b.readString()
  of 2'u16: into.url = b.readString()
  of 3'u16: into.icon = b.readOptString()
  else: discard

proc writeNavItem*(b: var Buffer, item: BooyakaNavItem) =
  ## Nil encodes as absent (`false`); present items as (`true` + struct)
  b.writeBool(not item.isNil)
  if not item.isNil:
    b.beginInnerStruct(DbCodecVersion)
    writeNavItemFields(b, item)
    b.endInnerStruct()

proc readNavItem*(b: var Buffer): BooyakaNavItem =
  if not b.readBool():
    return nil
  result = BooyakaNavItem()
  var outVer: uint32
  b.decodeInnerInto(result, handleNavItemField, outVer)

proc writeNavItemSeq*(b: var Buffer, items: seq[BooyakaNavItem]) =
  writeVector[BooyakaNavItem](b, items,
    proc (bb: var Buffer, it: BooyakaNavItem) = bb.writeNavItem(it))

proc readNavItemSeq*(b: var Buffer): seq[BooyakaNavItem] =
  readVector[BooyakaNavItem](b,
    proc (bb: var Buffer): BooyakaNavItem = bb.readNavItem())

proc writeOptNavItem*(b: var Buffer, v: Option[BooyakaNavItem]) =
  let item = v.get(nil)
  writeOptional[BooyakaNavItem](b, v.isSome, item,
    proc (bb: var Buffer, it: BooyakaNavItem) = bb.writeNavItem(it))

proc readOptNavItem*(b: var Buffer): Option[BooyakaNavItem] =
  var has = false
  let item = readOptional[BooyakaNavItem](b, 
    proc (bb: var Buffer): BooyakaNavItem = bb.readNavItem(), has)
  if has: some(item) else: none(BooyakaNavItem)

proc writeNavSectionFields(b: var Buffer, s: NavigationSection) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeString(s.name))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeNavItemSeq(s.items))

proc handleNavSectionField(fid: uint16, fsz: int, b: var Buffer,
                           into: var NavigationSection) =
  case fid
  of 1'u16: into.name = b.readString()
  of 2'u16: into.items = b.readNavItemSeq()
  else: discard

proc writeNavSection*(b: var Buffer, s: NavigationSection) =
  b.writeBool(not s.isNil)
  if not s.isNil:
    b.beginInnerStruct(DbCodecVersion)
    writeNavSectionFields(b, s)
    b.endInnerStruct()

proc readNavSection*(b: var Buffer): NavigationSection =
  if not b.readBool():
    return nil
  result = NavigationSection()
  var outVer: uint32
  b.decodeInnerInto(result, handleNavSectionField, outVer)

proc writeNavSectionSeq*(b: var Buffer, items: seq[NavigationSection]) =
  writeVector[NavigationSection](b, items,
    proc (bb: var Buffer, it: NavigationSection) = bb.writeNavSection(it))

proc readNavSectionSeq*(b: var Buffer): seq[NavigationSection] =
  readVector[NavigationSection](b,
    proc (bb: var Buffer): NavigationSection = bb.readNavSection())

# ---------------------------------------------------------------------------
# Enums (explicit ordinals; unknown values fall back to defaults)
# ---------------------------------------------------------------------------

proc writeSidebarType*(b: var Buffer, v: SidebarType) =
  b.writeInt32LE(int32(ord(v)))

proc readSidebarType*(b: var Buffer): SidebarType =
  let o = int(b.readInt32LE())
  if o >= ord(low(SidebarType)) and o <= ord(high(SidebarType)):
    cast[SidebarType](o)
  else:
    sidebarTypeNone

proc writeTheme*(b: var Buffer, v: AppearanceDefaultTheme) =
  b.writeInt32LE(int32(ord(v)))

proc readTheme*(b: var Buffer): AppearanceDefaultTheme =
  let o = int(b.readInt32LE())
  if o >= ord(low(AppearanceDefaultTheme)) and o <= ord(high(AppearanceDefaultTheme)):
    cast[AppearanceDefaultTheme](o)
  else:
    themeSystem

proc writeHtmlTag*(b: var Buffer, v: HtmlTag) =
  b.writeInt32LE(int32(ord(v)))

proc readHtmlTag*(b: var Buffer): HtmlTag =
  let o = int(b.readInt32LE())
  if o >= ord(low(HtmlTag)) and o <= ord(high(HtmlTag)):
    cast[HtmlTag](o)
  else:
    low(HtmlTag)

proc writeHtmlTagSeq*(b: var Buffer, items: seq[HtmlTag]) =
  writeVector[HtmlTag](b, items,
    proc (bb: var Buffer, t: HtmlTag) = bb.writeHtmlTag(t))

proc readHtmlTagSeq*(b: var Buffer): seq[HtmlTag] =
  readVector[HtmlTag](b,
    proc (bb: var Buffer): HtmlTag = bb.readHtmlTag())

# ---------------------------------------------------------------------------
# BooyakaConfig tree
# ---------------------------------------------------------------------------

proc writeShareProviderFields(b: var Buffer, p: ShareProvider) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeString(p.label))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeString(p.url))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeOptString(p.icon))
  b.writeField(4'u16, proc (bb: var Buffer) = bb.writeString(p.description))

proc handleShareProviderField(fid: uint16, fsz: int, b: var Buffer,
                              into: var ShareProvider) =
  case fid
  of 1'u16: into.label = b.readString()
  of 2'u16: into.url = b.readString()
  of 3'u16: into.icon = b.readOptString()
  of 4'u16: into.description = b.readString()
  else: discard

proc writeShareProvider*(b: var Buffer, p: ShareProvider) =
  b.beginInnerStruct(DbCodecVersion)
  writeShareProviderFields(b, p)
  b.endInnerStruct()

proc readShareProvider*(b: var Buffer): ShareProvider =
  var outVer: uint32
  b.decodeInnerInto(result, handleShareProviderField, outVer)

proc writeSidebarSectionFields(b: var Buffer, s: SidebarSection) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeOptString(s.title))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeOptString(s.content))

proc handleSidebarSectionField(fid: uint16, fsz: int, b: var Buffer,
                               into: var SidebarSection) =
  case fid
  of 1'u16: into.title = b.readOptString()
  of 2'u16: into.content = b.readOptString()
  else: discard

proc writeSidebarSection*(b: var Buffer, s: SidebarSection) =
  b.beginInnerStruct(DbCodecVersion)
  writeSidebarSectionFields(b, s)
  b.endInnerStruct()

proc readSidebarSection*(b: var Buffer): SidebarSection =
  var outVer: uint32
  b.decodeInnerInto(result, handleSidebarSectionField, outVer)

proc writeMetadataFields(b: var Buffer, m: BooyakaMetadata) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeString(m.url))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeOptString(m.logo))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeBool(m.logo_keep_gradient))
  b.writeField(4'u16, proc (bb: var Buffer) = bb.writeOptString(m.title))
  b.writeField(5'u16, proc (bb: var Buffer) = bb.writeOptString(m.description))
  b.writeField(6'u16, proc (bb: var Buffer) = bb.writeOptStrSeq(m.keywords))

proc handleMetadataField(fid: uint16, fsz: int, b: var Buffer,
                         into: var BooyakaMetadata) =
  case fid
  of 1'u16: into.url = b.readString()
  of 2'u16: into.logo = b.readOptString()
  of 3'u16: into.logo_keep_gradient = b.readBool()
  of 4'u16: into.title = b.readOptString()
  of 5'u16: into.description = b.readOptString()
  of 6'u16: into.keywords = b.readOptStrSeq()
  else: discard

proc writeMetadata*(b: var Buffer, m: BooyakaMetadata) =
  b.beginInnerStruct(DbCodecVersion)
  writeMetadataFields(b, m)
  b.endInnerStruct()

proc readMetadata*(b: var Buffer): BooyakaMetadata =
  var outVer: uint32
  b.decodeInnerInto(result, handleMetadataField, outVer)

# ---------------------------------------------------------------------------
# Optional sequences of composite types
# ---------------------------------------------------------------------------

proc writeOptHtmlTagSeq*(b: var Buffer, v: Option[seq[HtmlTag]]) =
  let items = v.get(@[])
  writeOptional[seq[HtmlTag]](b, v.isSome, items,
    proc (bb: var Buffer, xs: seq[HtmlTag]) = bb.writeHtmlTagSeq(xs))

proc readOptHtmlTagSeq*(b: var Buffer): Option[seq[HtmlTag]] =
  var has = false
  let items = readOptional[seq[HtmlTag]](b, 
    proc (bb: var Buffer): seq[HtmlTag] = bb.readHtmlTagSeq(), has)
  if has: some(items) else: none(seq[HtmlTag])

proc writeShareProviderSeq*(b: var Buffer, items: seq[ShareProvider]) =
  writeVector[ShareProvider](b, items,
    proc (bb: var Buffer, p: ShareProvider) = bb.writeShareProvider(p))

proc readShareProviderSeq*(b: var Buffer): seq[ShareProvider] =
  readVector[ShareProvider](b,
    proc (bb: var Buffer): ShareProvider = bb.readShareProvider())

proc writeOptShareProviderSeq*(b: var Buffer, v: Option[seq[ShareProvider]]) =
  let items = v.get(@[])
  writeOptional[seq[ShareProvider]](b, v.isSome, items,
    proc (bb: var Buffer, xs: seq[ShareProvider]) = bb.writeShareProviderSeq(xs))

proc readOptShareProviderSeq*(b: var Buffer): Option[seq[ShareProvider]] =
  var has = false
  let items = readOptional[seq[ShareProvider]](b, 
    proc (bb: var Buffer): seq[ShareProvider] = bb.readShareProviderSeq(), has)
  if has: some(items) else: none(seq[ShareProvider])

proc writeOptNavItemSeq*(b: var Buffer, v: Option[seq[BooyakaNavItem]]) =
  let items = v.get(@[])
  writeOptional[seq[BooyakaNavItem]](b, v.isSome, items,
    proc (bb: var Buffer, xs: seq[BooyakaNavItem]) = bb.writeNavItemSeq(xs))

proc readOptNavItemSeq*(b: var Buffer): Option[seq[BooyakaNavItem]] =
  var has = false
  let items = readOptional[seq[BooyakaNavItem]](b, 
    proc (bb: var Buffer): seq[BooyakaNavItem] = bb.readNavItemSeq(), has)
  if has: some(items) else: none(seq[BooyakaNavItem])

proc writeSidebarSectionSeq*(b: var Buffer, items: seq[SidebarSection]) =
  writeVector[SidebarSection](b, items,
    proc (bb: var Buffer, s: SidebarSection) = bb.writeSidebarSection(s))

proc readSidebarSectionSeq*(b: var Buffer): seq[SidebarSection] =
  readVector[SidebarSection](b,
    proc (bb: var Buffer): SidebarSection = bb.readSidebarSection())

proc writeOptSidebarSectionSeq*(b: var Buffer, v: Option[seq[SidebarSection]]) =
  let items = v.get(@[])
  writeOptional[seq[SidebarSection]](b, v.isSome, items,
    proc (bb: var Buffer, xs: seq[SidebarSection]) = bb.writeSidebarSectionSeq(xs))

proc readOptSidebarSectionSeq*(b: var Buffer): Option[seq[SidebarSection]] =
  var has = false
  let items = readOptional[seq[SidebarSection]](b, 
    proc (bb: var Buffer): seq[SidebarSection] = bb.readSidebarSectionSeq(), has)
  if has: some(items) else: none(seq[SidebarSection])

# ---------------------------------------------------------------------------
# ContentSettings
# ---------------------------------------------------------------------------

proc writeContentFields(b: var Buffer, c: ContentSettings) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeOptHtmlTagSeq(c.allowedRawHtmlTags))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeBool(c.showLastUpdated))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeString(c.lastDateUpdatedFormat))
  b.writeField(4'u16, proc (bb: var Buffer) = bb.writeBool(c.enableAutoFormatLinks))
  b.writeField(5'u16, proc (bb: var Buffer) = bb.writeBool(c.bottom_navigation))
  b.writeField(6'u16, proc (bb: var Buffer) = bb.writeString(c.codeHighlightTheme))
  b.writeField(7'u16, proc (bb: var Buffer) = bb.writeBool(c.share_ai_buttons))
  b.writeField(8'u16, proc (bb: var Buffer) = bb.writeOptShareProviderSeq(c.share_buttons_ai_providers))
  b.writeField(9'u16, proc (bb: var Buffer) = bb.writeBool(c.lazyloadIframes))
  b.writeField(10'u16, proc (bb: var Buffer) = bb.writeBool(c.lazyloadVideos))
  b.writeField(11'u16, proc (bb: var Buffer) = bb.writeBool(c.lazyloadImages))
  b.writeField(12'u16, proc (bb: var Buffer) = bb.writeBool(c.pageReferences))

proc handleContentField(fid: uint16, fsz: int, b: var Buffer,
                        into: var ContentSettings) =
  case fid
  of 1'u16: into.allowedRawHtmlTags = b.readOptHtmlTagSeq()
  of 2'u16: into.showLastUpdated = b.readBool()
  of 3'u16: into.lastDateUpdatedFormat = b.readString()
  of 4'u16: into.enableAutoFormatLinks = b.readBool()
  of 5'u16: into.bottom_navigation = b.readBool()
  of 6'u16: into.codeHighlightTheme = b.readString()
  of 7'u16: into.share_ai_buttons = b.readBool()
  of 8'u16: into.share_buttons_ai_providers = b.readOptShareProviderSeq()
  of 9'u16: into.lazyloadIframes = b.readBool()
  of 10'u16: into.lazyloadVideos = b.readBool()
  of 11'u16: into.lazyloadImages = b.readBool()
  of 12'u16: into.pageReferences = b.readBool()
  else: discard

proc writeContent*(b: var Buffer, c: ContentSettings) =
  b.beginInnerStruct(DbCodecVersion)
  writeContentFields(b, c)
  b.endInnerStruct()

proc readContent*(b: var Buffer): ContentSettings =
  var outVer: uint32
  b.decodeInnerInto(result, handleContentField, outVer)

# ---------------------------------------------------------------------------
# Header / appearance / git / footer / extra sections
# ---------------------------------------------------------------------------

proc writeHeaderSearchFields(b: var Buffer, s: HeaderSearchSettings) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeBool(s.enable))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeBool(s.index_meta_data))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeBool(s.index_page_titles))

proc handleHeaderSearchField(fid: uint16, fsz: int, b: var Buffer,
                             into: var HeaderSearchSettings) =
  case fid
  of 1'u16: into.enable = b.readBool()
  of 2'u16: into.index_meta_data = b.readBool()
  of 3'u16: into.index_page_titles = b.readBool()
  else: discard

proc writeHeaderSearch*(b: var Buffer, s: HeaderSearchSettings) =
  b.beginInnerStruct(DbCodecVersion)
  writeHeaderSearchFields(b, s)
  b.endInnerStruct()

proc readHeaderSearch*(b: var Buffer): HeaderSearchSettings =
  var outVer: uint32
  b.decodeInnerInto(result, handleHeaderSearchField, outVer)

proc writeHeaderFields(b: var Buffer, h: HeaderSettings) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeHeaderSearch(h.search))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeOptString(h.notification))

proc handleHeaderField(fid: uint16, fsz: int, b: var Buffer,
                       into: var HeaderSettings) =
  case fid
  of 1'u16: into.search = b.readHeaderSearch()
  of 2'u16: into.notification = b.readOptString()
  else: discard

proc writeHeader*(b: var Buffer, h: HeaderSettings) =
  b.beginInnerStruct(DbCodecVersion)
  writeHeaderFields(b, h)
  b.endInnerStruct()

proc readHeader*(b: var Buffer): HeaderSettings =
  var outVer: uint32
  b.decodeInnerInto(result, handleHeaderField, outVer)

proc writeAppearanceFields(b: var Buffer, a: AppearanceSettings) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeBool(a.show_theme_switcher))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeTheme(a.default_theme))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeBool(a.show_toggle_left_sidebar))
  b.writeField(4'u16, proc (bb: var Buffer) = bb.writeBool(a.show_toggle_right_sidebar))
  b.writeField(5'u16, proc (bb: var Buffer) = bb.writeString(a.container_width))
  b.writeField(6'u16, proc (bb: var Buffer) = bb.writeString(a.content_width))
  b.writeField(7'u16, proc (bb: var Buffer) = bb.writeFloat64LE(a.background_noise_opacity))

proc handleAppearanceField(fid: uint16, fsz: int, b: var Buffer,
                           into: var AppearanceSettings) =
  case fid
  of 1'u16: into.show_theme_switcher = b.readBool()
  of 2'u16: into.default_theme = b.readTheme()
  of 3'u16: into.show_toggle_left_sidebar = b.readBool()
  of 4'u16: into.show_toggle_right_sidebar = b.readBool()
  of 5'u16: into.container_width = b.readString()
  of 6'u16: into.content_width = b.readString()
  of 7'u16: into.background_noise_opacity = b.readFloat64LE()
  else: discard

proc writeAppearance*(b: var Buffer, a: AppearanceSettings) =
  b.beginInnerStruct(DbCodecVersion)
  writeAppearanceFields(b, a)
  b.endInnerStruct()

proc readAppearance*(b: var Buffer): AppearanceSettings =
  var outVer: uint32
  b.decodeInnerInto(result, handleAppearanceField, outVer)

proc writeGitFields(b: var Buffer, g: GitSettings) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeBool(g.enable_versioning))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeBool(g.enable_contributors_info))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeString(g.latest_label))

proc handleGitField(fid: uint16, fsz: int, b: var Buffer,
                    into: var GitSettings) =
  case fid
  of 1'u16: into.enable_versioning = b.readBool()
  of 2'u16: into.enable_contributors_info = b.readBool()
  of 3'u16: into.latest_label = b.readString()
  else: discard

proc writeGit*(b: var Buffer, g: GitSettings) =
  b.beginInnerStruct(DbCodecVersion)
  writeGitFields(b, g)
  b.endInnerStruct()

proc readGit*(b: var Buffer): GitSettings =
  var outVer: uint32
  b.decodeInnerInto(result, handleGitField, outVer)

proc writeExtraSectionsFields(b: var Buffer, e: BooyakaExtraSections) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeOptSidebarSectionSeq(e.left_sidebar))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeOptSidebarSectionSeq(e.right_sidebar))

proc handleExtraSectionsField(fid: uint16, fsz: int, b: var Buffer,
                              into: var BooyakaExtraSections) =
  case fid
  of 1'u16: into.left_sidebar = b.readOptSidebarSectionSeq()
  of 2'u16: into.right_sidebar = b.readOptSidebarSectionSeq()
  else: discard

proc writeExtraSections*(b: var Buffer, e: BooyakaExtraSections) =
  b.beginInnerStruct(DbCodecVersion)
  writeExtraSectionsFields(b, e)
  b.endInnerStruct()

proc readExtraSections*(b: var Buffer): BooyakaExtraSections =
  var outVer: uint32
  b.decodeInnerInto(result, handleExtraSectionsField, outVer)

proc writeFooterFields(b: var Buffer, f: BooyakaFooter) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeOptString(f.text))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeOptNavItemSeq(f.links))

proc handleFooterField(fid: uint16, fsz: int, b: var Buffer,
                       into: var BooyakaFooter) =
  case fid
  of 1'u16: into.text = b.readOptString()
  of 2'u16: into.links = b.readOptNavItemSeq()
  else: discard

proc writeFooter*(b: var Buffer, f: BooyakaFooter) =
  b.beginInnerStruct(DbCodecVersion)
  writeFooterFields(b, f)
  b.endInnerStruct()

proc readFooter*(b: var Buffer): BooyakaFooter =
  var outVer: uint32
  b.decodeInnerInto(result, handleFooterField, outVer)

# ---------------------------------------------------------------------------
# BooyakaConfig root
# ---------------------------------------------------------------------------

proc writeConfigFields(b: var Buffer, c: BooyakaConfig) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeMetadata(c.metadata))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeAppearance(c.appearance))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeGit(c.git))
  b.writeField(4'u16, proc (bb: var Buffer) = bb.writeHeader(c.header))
  b.writeField(5'u16, proc (bb: var Buffer) = bb.writeContent(c.content))
  b.writeField(6'u16, proc (bb: var Buffer) = bb.writeOptNavItemSeq(c.navbar))
  b.writeField(7'u16, proc (bb: var Buffer) = bb.writeNavSectionSeq(c.sidebar_navigation))
  b.writeField(8'u16, proc (bb: var Buffer) = bb.writeSidebarType(c.sidebarLeftType))
  b.writeField(9'u16, proc (bb: var Buffer) = bb.writeSidebarType(c.sidebarRightType))
  b.writeField(10'u16, proc (bb: var Buffer) = bb.writeExtraSections(c.extra_sections))
  b.writeField(11'u16, proc (bb: var Buffer) = bb.writeFooter(c.footer))

proc handleConfigField(fid: uint16, fsz: int, b: var Buffer,
                       into: var BooyakaConfig) =
  case fid
  of 1'u16: into.metadata = b.readMetadata()
  of 2'u16: into.appearance = b.readAppearance()
  of 3'u16: into.git = b.readGit()
  of 4'u16: into.header = b.readHeader()
  of 5'u16: into.content = b.readContent()
  of 6'u16: into.navbar = b.readOptNavItemSeq()
  of 7'u16: into.sidebar_navigation = b.readNavSectionSeq()
  of 8'u16: into.sidebarLeftType = b.readSidebarType()
  of 9'u16: into.sidebarRightType = b.readSidebarType()
  of 10'u16: into.extra_sections = b.readExtraSections()
  of 11'u16: into.footer = b.readFooter()
  else: discard

proc writeConfig*(b: var Buffer, c: BooyakaConfig) =
  b.beginInnerStruct(DbCodecVersion)
  writeConfigFields(b, c)
  b.endInnerStruct()

proc readConfig*(b: var Buffer): BooyakaConfig =
  var outVer: uint32
  b.decodeInnerInto(result, handleConfigField, outVer)

# ---------------------------------------------------------------------------
# MarkdownPage
# ---------------------------------------------------------------------------

proc writePageNavFields(b: var Buffer, n: MarkdownPageBottomNavigation) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeOptNavItem(n.previous))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeOptNavItem(n.next))

proc handlePageNavField(fid: uint16, fsz: int, b: var Buffer,
                        into: var MarkdownPageBottomNavigation) =
  case fid
  of 1'u16: into.previous = b.readOptNavItem()
  of 2'u16: into.next = b.readOptNavItem()
  else: discard

proc writePageNav*(b: var Buffer, n: MarkdownPageBottomNavigation) =
  b.beginInnerStruct(DbCodecVersion)
  writePageNavFields(b, n)
  b.endInnerStruct()

proc readPageNav*(b: var Buffer): MarkdownPageBottomNavigation =
  var outVer: uint32
  b.decodeInnerInto(result, handlePageNavField, outVer)

proc writePageFields(b: var Buffer, p: MarkdownPage) =
  b.writeField(1'u16, proc (bb: var Buffer) = bb.writeJsonNode(p.meta))
  b.writeField(2'u16, proc (bb: var Buffer) = bb.writeString(p.title))
  b.writeField(3'u16, proc (bb: var Buffer) = bb.writeString(p.section))
  b.writeField(4'u16, proc (bb: var Buffer) = bb.writeString(p.content))
  b.writeField(5'u16, proc (bb: var Buffer) = bb.writeString(p.last_updated))
  b.writeField(6'u16, proc (bb: var Buffer) = bb.writeOrderedStrMap(p.toc))
  b.writeField(7'u16, proc (bb: var Buffer) = bb.writeString(p.tocHtml))
  b.writeField(8'u16, proc (bb: var Buffer) = bb.writeString(p.markdownSourceJson))
  b.writeField(9'u16, proc (bb: var Buffer) = bb.writePageNav(p.navigation))
  b.writeField(10'u16, proc (bb: var Buffer) = bb.writeOptTime(p.lastEdited))

proc handlePageField(fid: uint16, fsz: int, b: var Buffer,
                     into: var MarkdownPage) =
  case fid
  of 1'u16: into.meta = b.readJsonNode()
  of 2'u16: into.title = b.readString()
  of 3'u16: into.section = b.readString()
  of 4'u16: into.content = b.readString()
  of 5'u16: into.last_updated = b.readString()
  of 6'u16: into.toc = b.readOrderedStrMap()
  of 7'u16: into.tocHtml = b.readString()
  of 8'u16: into.markdownSourceJson = b.readString()
  of 9'u16: into.navigation = b.readPageNav()
  of 10'u16: into.lastEdited = b.readOptTime()
  else: discard

proc writeMarkdownPage*(b: var Buffer, p: MarkdownPage) =
  b.beginInnerStruct(DbCodecVersion)
  writePageFields(b, p)
  b.endInnerStruct()

proc readMarkdownPage*(b: var Buffer): MarkdownPage =
  var outVer: uint32
  b.decodeInnerInto(result, handlePageField, outVer)

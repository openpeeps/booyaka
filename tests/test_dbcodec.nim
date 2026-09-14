# Round-trip tests for the FBE database codecs (dbcodec)
import std/[unittest, options, tables, times]
import pkg/semver
import pkg/openparser/fbe
import pkg/openparser/json
import ../src/service/provider/dbcodec
import ../src/app/structs

suite "dbcodec envelope":
  test "writeDbFile/readDbFile round-trip":
    var payload = initBuffer()
    payload.writeString("hello-payload")
    writeDbFile("/tmp/fbe_test_envelope.db", payload)
    var outPayload: Buffer
    check readDbFile("/tmp/fbe_test_envelope.db", outPayload) == dbOk
    check outPayload.readString() == "hello-payload"

  test "missing file reports dbMissing":
    var outPayload: Buffer
    check readDbFile("/tmp/fbe_test_nonexistent_xyz.db", outPayload) == dbMissing

  test "foreign bytes report dbInvalid":
    writeFile("/tmp/fbe_test_foreign.db", "this is a flatty-era blob")
    var outPayload: Buffer
    check readDbFile("/tmp/fbe_test_foreign.db", outPayload) == dbInvalid

  test "wrong booyaka version reports dbVersionMismatch":
    var payload = initBuffer()
    payload.writeString("x")
    var b = initBuffer()
    b.writeString(DbMagic)
    b.writeUint32LE(DbCodecVersion)
    b.writeString("0.0.0-fake")
    b.writeBytes(payload.data)
    writeFile("/tmp/fbe_test_badver.db", bufferToString(b))
    var outPayload: Buffer
    check readDbFile("/tmp/fbe_test_badver.db", outPayload) == dbVersionMismatch

suite "dbcodec primitives":
  test "Option[string] round-trip incl. none":
    for v in [some("abc"), none(string)]:
      var b = initBuffer()
      b.writeOptString(v)
      b.pos = 0
      check b.readOptString() == v

  test "Time round-trip (second precision)":
    let t = getTime()
    var b = initBuffer()
    b.writeUnixTime(t)
    b.pos = 0
    check b.readUnixTime().toUnix() == t.toUnix()

  test "JsonNode round-trip incl. nil":
    let n = fromJson("""{"title": "Hi", "n": 3}""")
    var b = initBuffer()
    b.writeJsonNode(n)
    b.pos = 0
    let back = b.readJsonNode()
    check back["title"].getStr() == "Hi"
    var b2 = initBuffer()
    b2.writeJsonNode(nil)
    b2.pos = 0
    check b2.readJsonNode().isNil

  test "string tables round-trip":
    var t = newTable[string, string]()
    t["/a"] = "hash1"
    var b = initBuffer()
    b.writeStrMap(t)
    b.pos = 0
    let back = b.readStrMap()
    check back["/a"] == "hash1"
    var b2 = initBuffer()
    b2.writeStrMap(nil)
    b2.pos = 0
    check b2.readStrMap().len == 0

suite "dbcodec entities":
  test "MarkdownPage round-trip":
    var page = MarkdownPage(
      meta: fromJson("""{"title": "T", "description": "D"}"""),
      title: "T",
      section: "sec",
      content: "<p>hi</p>",
      last_updated: "2026-01-01",
      toc: newOrderedTable[string, string](),
      tocHtml: "<ul></ul>",
      markdownSourceJson: "{}",
      navigation: MarkdownPageBottomNavigation(
        previous: some(BooyakaNavItem(title: "P", url: "/p", icon: none(string))),
        next: none(BooyakaNavItem)),
      lastEdited: some(getTime()))
    page.toc["H"] = "#h"
    var b = initBuffer()
    b.beginInnerStruct(DbCodecVersion)
    b.writeField(1'u16, proc (bb: var Buffer) = bb.writeMarkdownPage(page))
    b.endInnerStruct()
    b.pos = 0
    var outVer: uint32
    var back: MarkdownPage
    b.decodeInnerInto(back, proc (fid: uint16, fsz: int, bb: var Buffer, into: var MarkdownPage) =
      if fid == 1'u16: into = bb.readMarkdownPage(),
      outVer)
    check back.title == "T"
    check back.meta["description"].getStr() == "D"
    check back.toc["H"] == "#h"
    check back.navigation.previous.get().url == "/p"
    check back.navigation.next.isNone
    check back.lastEdited.get().toUnix() == page.lastEdited.get().toUnix()

  test "semver.Version round-trip":
    let v = newVersion(1, 2, 3)
    var b = initBuffer()
    b.writeSemverVersion(v)
    b.pos = 0
    let back = b.readSemverVersion()
    check (back.major, back.minor, back.patch) == (1, 2, 3)

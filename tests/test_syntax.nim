import std/[unittest, os, strutils]
import pkg/marvdown

import ../src/service/provider/syntax

suite "sweetsyntax backend highlighting":
  test "known language emits spans":
    let html = highlightCode("nim", "import std/os\n")
    check html.contains("<span")
    check html.contains("import")

  test "unknown language falls back to escaped code":
    let html = highlightCode("notalang", "<b>hi</b>")
    check not html.contains("<span")
    check html.contains("&lt;b&gt;hi&lt;/b&gt;")

  test "empty language returns escaped code":
    check highlightCode("", "a < b") == "a &lt; b"

  test "highlight never raises on broken code":
    let html = highlightCode("js", "function (broken {{{")
    check html.len > 0

  test "custom yaml spec loads from a syntax dir":
    let dir = getTempDir() / "booyaka_syntax_test"
    createDir(dir)
    writeFile(dir / "mylang.yaml",
      "name: \"MyLang\"\nextension: [\".mylang\"]\n")
    clearSyntaxCache()
    check loadSyntaxDir(dir) == 1
    let html = highlightCode("mylang", "hello world")
    check html.contains("<span")
    clearSyntaxCache()

  test "missing syntax dir is a no-op":
    clearSyntaxCache()
    check loadSyntaxDir(getTempDir() / "booyaka_syntax_missing_xyz") == 0
    clearSyntaxCache()

suite "marvdown codeBlockTransform hook":
  test "hook output replaces default code block":
    var opts = MarkdownOptions()
    opts.codeBlockTransform = highlightCode
    var md = newMarkdown("```nim\nimport std/os\n```\n", opts)
    let html = md.toHtml()
    check html.contains("<span")
    check html.contains("language-nim")

  test "nil hook keeps default escaped output":
    var opts = MarkdownOptions()
    var md = newMarkdown("```nim\na < b\n```\n", opts)
    let html = md.toHtml()
    check not html.contains("<span")
    check html.contains("a &lt; b")

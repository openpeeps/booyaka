# Booyaka - A documentation site generator for cool kids!
#
# (c) 2026 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

## Backend syntax highlighting for fenced code blocks via SweetSyntax.
##
## Custom language specs (`*.yaml`) ship inside themes (`themes/<name>/syntax/`)
## and are probed before SweetSyntax built-ins. Unknown languages or any
## lexer failure falls back to plain escaped code, so page rendering
## can never break because of highlighting.

import std/[os, tables, strutils]

import pkg/sweetsyntax
import pkg/sweetsyntax/renderers/[highlight, htmlrenderer]

var customSpecs* = initTable[string, SweetSpec]()
  ## Custom language specs loaded from theme `syntax/` dirs,
  ## keyed by lowercase language name (filename base + spec extensions).

const langAliases = {
  "javascript": "js", "typescript": "js", "jsx": "js", "tsx": "js",
  "python": "py", "pyw": "py",
  "markdown": "md", "mdown": "md", "mkd": "md",
  "cpp": "c", "cc": "c", "hpp": "c", "h": "c",
  "ruby": "rb", "golang": "go",
  "nims": "nim",
}.toTable

proc normalizeLang*(lang: string): string =
  ## Normalizes a fence info string to a lookup key: lowercase, first word
  ## only (` ```nim linenums ` -> `nim`), with common aliases resolved.
  var key = lang.strip().toLowerAscii()
  let spaceIdx = key.find(' ')
  if spaceIdx > 0:
    key = key[0 ..< spaceIdx]
  if langAliases.hasKey(key):
    return langAliases[key]
  key

proc escapeCodeHtml*(s: string): string =
  ## Plain fallback: HTML-escape code without any highlighting.
  ## Mirrors marvdown's default code block escaping.
  result = s.multiReplace(("&", "&amp;"), ("<", "&lt;"),
                          (">", "&gt;"), ("\"", "&quot;"))

proc loadSyntaxDir*(dir: string): int =
  ## Loads every `*.yaml` spec from `dir` into the custom specs table.
  ## Each file registers under its lowercase basename plus every extension
  ## declared in the spec. Returns the number of files loaded.
  ## Missing dirs are a no-op (returns 0).
  result = 0
  if not dirExists(dir):
    return
  for path in walkDirRec(dir, {pcFile}):
    if not path.endsWith(".yaml"):
      continue
    if extractFilename(path).startsWith("."):
      continue
    try:
      let spec = newSyntax(path).spec
      let base = splitFile(path).name.toLowerAscii()
      customSpecs[base] = spec
      for ext in spec.extension:
        let key = ext.strip(chars = {'.'}).toLowerAscii()
        if key.len > 0:
          customSpecs[key] = spec
      inc result
    except CatchableError:
      continue

proc clearSyntaxCache*() =
  ## Empties the custom specs table (used in tests and theme reloads).
  customSpecs.clear()

proc highlightCode*(lang, code: string): string =
  ## Highlights `code` for backend rendering inside `<pre><code>`.
  ## Returns span-annotated HTML, or plain escaped code when the language
  ## is unknown/empty or highlighting fails. Never raises.
  let key = normalizeLang(lang)
  if key.len == 0:
    return escapeCodeHtml(code.strip())
  if customSpecs.hasKey(key):
    try:
      var lx = initLexer(customSpecs[key], code)
      return highlightHtml(lx)
    except CatchableError:
      return escapeCodeHtml(code.strip())
  try:
    let known = syntaxForExt(key)
    return highlight(known, code, hfHtml)
  except CatchableError:
    return escapeCodeHtml(code.strip())

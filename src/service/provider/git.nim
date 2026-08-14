# Booyaka - A documentation site generator for cool kids!
#
# (c) 2025 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/booyaka

## This Service provides Git integration for Booyaka's versioned documentation.
##
## It detects semantic-version git tags in the project repository, extracts the
## markdown content of each tag into a local snapshot directory, and exposes the
## detected versions to the rest of the application.
##
## Versioning is purely opt-in (via `git.enable_versioning`) and degrades
## gracefully when the project is not a git repository or git is unavailable.

import std/[os, strutils, osproc, algorithm]

import pkg/semver

const
  versionsCacheDir* = ".cache" / "versions"
    ## Directory (relative to the project path) where extracted
    ## tag snapshots are stored

proc isGitRepo*(projectPath: string): bool =
  ## Returns `true` when `projectPath` is inside a git repository
  dirExists(projectPath / ".git") or
    execCmdEx("git -C \"" & projectPath & "\" rev-parse --is-inside-work-tree").exitCode == 0

proc getSemverTags*(projectPath: string): seq[string] =
  ## Lists all git tags that parse as a semantic version, sorted descending.
  ## A leading `v` (e.g. `v1.0.0`) is accepted and stripped for comparison.
  if not isGitRepo(projectPath):
    return
  let (output, exitCode) =
    execCmdEx("git -C \"" & projectPath & "\" tag --list")
  if exitCode != 0 or output.len == 0:
    return
  var versions: seq[(Version, string)]
  for line in output.splitLines:
    let tag = line.strip()
    if tag.len == 0:
      continue
    try:
      versions.add((parseVersion(tag), tag))
    except ParseError:
      discard # skip non-semver tags
  versions.sort(
    proc(a, b: (Version, string)): int =
      if a[0] > b[0]: -1 # descending
      elif a[0] < b[0]: 1
      else: 0
  )
  for v in versions:
    result.add(v[1])

proc extractTag*(projectPath, tag, destDir: string) =
  ## Extracts the full tree of `tag` into `destDir` using `git archive`.
  ## The archive is piped to `tar` so the repository working tree is left
  ## untouched (read-only operation).
  createDir(destDir)
  let cmd = "git -C \"" & projectPath & "\" archive \"" & tag & "\" | tar -x -C \"" & destDir & "\""
  discard execCmd(cmd)

proc getVersionsCachePath*(projectPath: string): string =
  ## Returns the absolute path where tag snapshots are extracted
  projectPath / versionsCacheDir

proc getTagContentsPath*(projectPath, tag: string): string =
  ## Returns the absolute path of the extracted `contents` directory for a tag
  getVersionsCachePath(projectPath) / tag / "contents"

# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A fast documentation generator for cool kids!"
license       = "AGPL-3.0-or-later"
srcDir        = "src"
bin           = @["booyaka"]
binDir        = "build"

# Dependencies

requires "nim >= 2.0.0"
requires "supranim#head"
requires "tim#head"
requires "limiter#head"
requires "marvdown#head"
requires "jsony"
requires "flatty"
requires "supersnappy"
requires "semver"
requires "iconim"

requires "htmlparser#head"
# requires "https://github.com/openpeeps/pluginkit"
requires "pluginkit"

# Supra is not really a dependency but we want to ensure 
# it's available when building the release version of Booyaka
# so we can use Supra's CLI `bundle` command to bundle
# static assets into the executable.
requires "https://github.com/supranim/supra"

task dev, "Generate a development build":
  exec "nimble build"

task prod, "Generate a production build":
  exec "nimble build -d:release"

import std/[os, strutils]
task services, "Build all services":
  # Discover and build all service providers
  for src in walkDir("./src/service"):
    let file = splitFile(src.path)
    if file.ext == ".nim":
      exec "nimble c --opt:speed -d:useMalloc --path: --mm:arc --out:./bin/" & bin[0] & "_" & file.name & " " & src.path

task service, "Build a Supranim Service":
  # Build a specific service by name
  let params = commandLineParams()
  exec "nimble c --opt:speed -d:useMalloc --path: --mm:arc --out:./bin/" & bin[0] & "_" & params[^1] & " ./src/service/" & params[^1] & ".nim"

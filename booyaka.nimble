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
requires "supranim >= 0.1.3"
requires "tim >= 0.2.6"
requires "marvdown >= 0.1.0"
requires "flatty >= 0.4.0"
requires "semver >= 1.2.3"
requires "iconim >= 0.1.0"
requires "pluginkit >= 0.1.0"
requires "openparser >= 0.1.2"
requires "emitter >= 0.2.1[powpow]"

# Supra is not really a dependency but we want to ensure 
# it's available when building the release version of Booyaka
# so we can use Supra's CLI `bundle` command to bundle static assets into the executable.
requires "supra >= 0.1.0"

import std/[macros, os]

--define:ssl
--deepCopy:on
--mm:arc
--define:webapp # todo supWebApp
--define:supraFileserver
--define:supranimUseGlobalOnRequest

--define:avx2
--passC:"-mavx2"
--passL:"-mavx2"

--define:supraBundleSkipPrefix
  # When defined, this flag tells Supra (Supranim's CLI) to skip prefixing
  # asset keys with the directory name when embedding assets

when defined supranimDebug:
  --define:checkBounds
  --define:assertions
  --define:useMalloc
  --passC:"-fsanitize=address -fno-omit-frame-pointer"
  --passL:"-fsanitize=address"

when not defined release:
  --define:timHotCode
else:
  --define:supranimEmbedConfig
    # Embed Supranim config files (config/*.yml) into the binary at
    # compile time instead of creating a config/ directory at runtime

  # Note: `src/storage/assets/` is intentionally NOT bundled. Theme assets
  # ship inside each theme bundle below and are seeded/copied from the
  # project at runtime.

  for themeDir in ["default"]:
    let outputEmbedTheme = getProjectPath().parentDir() / ".cache" / "embed_themes_" & themeDir & ".nim"
    let themePath = absolutePath(joinPath(getProjectPath() / "themes" / themeDir))
    if dirExists(themePath):
      exec "supra bundle.assets \"" & themePath & "\" \"" & outputEmbedTheme & "\""

  let outputSVGIcons = getProjectPath().parentDir() / ".cache" / "embed_storage_icons.nim"
  let iconsPath = absolutePath(joinPath(getProjectPath() / "storage", "icons"))
  if dirExists(iconsPath):
    exec "supra bundle.assets \"" & iconsPath & "\" \"" & outputSVGIcons & "\""
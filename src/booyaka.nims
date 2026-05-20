import std/[macros, os]

when defined(macosx):
  --passL:"/opt/local/lib/libevent.a"
  --passL:"/opt/local/lib/libevent_pthreads.a"
  --passC:"-I /opt/local/include"
  --passC:"-Wno-incompatible-function-pointer-types"
elif defined(linux):
  --passL:"-L/usr/local/lib/lib -L/usr/local/lib -Wl,-rpath,/usr/local/lib/lib -Wl,-rpath,/usr/local/lib -levent -levent_pthreads"
  # --passL:"/usr/lib/x86_64-linux-gnu/libevent.a"
  # --passL:"/usr/lib/x86_64-linux-gnu/libevent_pthreads.a"
  --passC:"-I /usr/include"

--mm:atomicArc
--deepCopy:on
--define:webapp # todo supWebApp
--define:ssl
--define:supraFileserver
# --define:supranimUseGlobalOnRequest

--define:avx2
--passC:"-mavx2"
--passL:"-mavx2"

--define:supraBundleSkipPrefix
  # When defined, this flag tells Supra (Supranim's CLI) to skip prefixing
  # asset keys with the directory name when embedding assets

when not defined release:
  --define:timHotCode
else:
  const embedAssetsPath {.strdefine.} = ""
  let outputEmbedAssets = getProjectPath().parentDir() / ".cache" / "embed_assets.nim"
  let assetsPath = absolutePath(joinPath(getProjectPath() / "storage", "assets"))
  if dirExists(assetsPath):
    exec "supra bundle.assets \"" & assetsPath & "\" \"" & outputEmbedAssets & "\""

  for dir in ["views", "layouts", "partials"]:
    let outputEmbedTemplates = getProjectPath().parentDir() / ".cache" / "embed_templates_" & dir & ".nim"
    let templatesPath = absolutePath(joinPath(getProjectPath() / "templates" / dir))
    if dirExists(templatesPath):
      exec "supra bundle.assets \"" & templatesPath & "\" \"" & outputEmbedTemplates & "\" --skip-prefix" 

  let outputSVGIcons = getProjectPath().parentDir() / ".cache" / "embed_storage_icons.nim"
  let iconsPath = absolutePath(joinPath(getProjectPath() / "storage", "icons"))
  if dirExists(iconsPath):
    exec "supra bundle.assets \"" & iconsPath & "\" \"" & outputSVGIcons & "\""
import std/[macros, os]

when defined(macosx):
  --passL:"/opt/local/lib/libevent.a"
  --passC:"-I /opt/local/include"
  --passC:"-Wno-incompatible-function-pointer-types"
elif defined(linux):
  --passL:"-L/usr/local/lib/lib -L/usr/local/lib -Wl,-rpath,/usr/local/lib/lib -Wl,-rpath,/usr/local/lib -levent"
  --passC:"-I /usr/include"

--mm:arc
--define:webapp # todo supWebApp
--define:ssl
--define:supraFileserver
--define:supranimUseGlobalOnRequest

when not defined release:
  --define:timHotCode
else:
  const embedAssetsPath {.strdefine.} = ""
  if embedAssetsPath.len != 0:
    let outputEmbedAssets = getProjectPath().parentDir() / ".cache" / "embed_assets.nim"
    let assetsPath = absolutePath(joinPath(getProjectPath() / "storage", embedAssetsPath))
    if dirExists(assetsPath):
      exec "supra bundle.assets \"" & assetsPath & "\" \"" & outputEmbedAssets & "\""
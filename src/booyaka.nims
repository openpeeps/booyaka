--passL:"/opt/local/lib/libssl.a"
--passL:"/opt/local/lib/libcrypto.a"
--passL:"/opt/local/lib/libevent.a"
--passC:"-I /opt/local/include"

--mm:arc
--define:webapp # todo supWebApp
--define:ssl
--deepcopy:on
--forceBuild:on
--define:useMalloc
--define:supraFileserver
when not defined release:
  --define:timHotCode
else:
  --passC:"-O3 -flto" # Optimize for speed
  --passL:"-flto"     # Link Time Optimization for smaller/faster binaries

--path:"/Users/georgelemon/Development/packages/tim-v2/tim/src"
--path:"/Users/georgelemon/Development/packages/watchout/src"
--path:"/Users/georgelemon/Development/packages/voodoo/src"
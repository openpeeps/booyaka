when defined(macosx):
  --passL:"/opt/local/lib/libssl.a"
  --passL:"/opt/local/lib/libcrypto.a"
  --passL:"/opt/local/lib/libevent.a"
  --passC:"-I /opt/local/include"
elif defined(linux):
  --passL:"/usr/local/lib/libssl.so"
  --passL:"/usr/local/lib/libcrypto.so"
  --passL:"/usr/local/lib/libevent.a"
  --passC:"-I /usr/local/include"

--mm:arc
--define:webapp # todo supWebApp
--define:ssl
--define:supraFileserver
--define:supranimUseGlobalOnRequest

when not defined release:
  --define:timHotCode
else:
  --passC:"-O3 -flto" # Optimize for speed
  --passL:"-flto"     # Link Time Optimization for smaller/faster binaries

when defined(macosx):
  --passL:"/opt/local/lib/libevent.a"
  --passC:"-I /opt/local/include"
elif defined(linux):
  --passL:"/usr/local/lib/libevent.a"
  --passC:"-I /usr/local/include"

--mm:arc
--define:webapp # todo supWebApp
--define:ssl
--define:supraFileserver
--define:supranimUseGlobalOnRequest

when not defined release:
  --define:timHotCode
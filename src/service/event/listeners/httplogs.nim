import std/[options, times, logging, strutils]

import supranim/service/events
import supranim/service/logger

listener "http.error":
  {.gcsafe.}:
    let x = args.get()
    httpLogger.log(lvlError, "$1 [$2] $3" % [x[1], $now(), x[0]])

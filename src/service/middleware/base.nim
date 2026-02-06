import std/times

import pkg/supranim/middleware
import pkg/limiter

var globalLimiter = Limiter(timeLimit: initDuration(seconds = 10))

newBaseMiddleware limitChecker:
  ## Checks if the request is coming from an IP
  ## address that is currently limited by the server
  when defined release:
    if not globalLimiter.hit(req.getIp):
      req.resp(code = HttpCode(429), "", res.getHeaders())
  else: discard

newBaseMiddleware uriChecker:
  ## Fix the trailing slash in the URI
  let path = req.getUriPath
  if path != "/" and path[^1] == '/':
    res.addHeader("Location", path[0..^2])
    req.resp(code = HttpCode(301), "", res.getHeaders())
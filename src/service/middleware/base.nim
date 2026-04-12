import std/times

import pkg/limiter
import pkg/supranim/middleware

var globalLimiter = Limiter(
  maximumHits: 200,
  timeLimit: initDuration(seconds = 20),
  timeToWait: initDuration(seconds = 30)
)

newBaseMiddleware limitChecker:
  ## Checks if the request is coming from an IP
  ## address that is currently limited by the server
  when defined release:
    case globalLimiter.hit(req.getIp):
    of LimitResult.lrLimited:
      req.resp(code = HttpCode(429), "Too Many Requests", res.getHeaders)
      return false
    of LimitResult.lrTarpit:
      # drop the request by closing the connection without sending a resp
      req.dropRequest()
      return false
    of LimitResult.lrAllowed:
      discard # next is not needed in a base middleware
  else: discard
  result = true


newBaseMiddleware uriChecker:
  ## Fix the trailing slash in the URI
  let path = req.getUriPath
  if path != "/" and path[^1] == '/':
    res.addHeader("Location", path[0..^2])
    req.resp(code = HttpCode(301), "", res.getHeaders())
    return false
  result = true

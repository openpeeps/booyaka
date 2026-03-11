import std/[macros, json, strutils, os,
        sequtils, httpcore, times, options]

import pkg/supranim/support/slug
import pkg/supranim/core/[services, paths]

import pkg/[tim, iconim, kapsis/cli]

export HttpCode, render, `&*`
export times.now, times.format

import ../../app/structs

initService Tim[Global]:
  # A singleton service that wraps the Tim Engine
  # and provides a simple interface to render HTML pages
  backend do:
    var timInstance*: TimEngine
    
    Icon.init(
      source = storagePath / "icons",
      default = "filled",
      stripAttrs = %*[]
    )

    proc init*(src, output, basePath: string; global = newJObject()) =
      ## Initialize Tim Engine as a singleton service
      timInstance = newTim(
        src = src,
        output = output,
        basePath = basePath,
        globalData = global
      )

      # predefine foreign functions
      timInstance.userScript.addProc("slugify", @[paramDef("s", ttyString)], ttyString,
        proc (args: StackView): Value =
          ## Convert a string to a URL-friendly slug
          return initValue(slugify(args[0].stringVal[]))
        )

      timInstance.userScript.addProc("dashboard", @[paramDef("x", ttyString)], ttyString,
        proc (args: StackView): Value =
          # prefix a link with `/dashboard/`
          return initValue("/dashboard/" & args[0].stringVal[])
        )

      timInstance.userScript.addProc("icon", @[paramDef("name", ttyString)], ttyString,
        proc (args: StackView): Value =
          # Return an HTML string for an icon
          let iconName = args[0].stringVal[]
          return initValue($icon(iconName))
        )
      tim.initCommonStorage:
        {
          "path": req.getUrl(),
          "currentYear": now().format("yyyy"),
          "site": {
            "logo": globalBooyakaConfig.metadata.logo.get("/assets/booyaka.png"),
          }
        }
      timInstance.precompile()

    proc getTimInstance*: TimEngine =
      # Returns the singleton instance of the Tim Engine
      if timInstance == nil:
        raise newException(ValueError, "Tim Engine not initialized")
      return timInstance

  client do:
    macro staticRender*() = 
      ## Traspiles the Tim template to Nim code for static site generation

    template render*(view: string, layout: string = "base",
                      httpCode = Http200, local: JsonNode = nil): untyped =
      ## Renders a Tim template and sends it as an HTTP response.
      ## It must be used within a route handler (controller).
      try:
        let output = render(timInstance, view, layout, local)
        respond(httpCode, output)
      except:
        let errMsg = getCurrentExceptionMsg()
        displayError("<runtime.exception> " & errMsg)
        try:
          let errorLocal = %*{"error": errMsg}
          respond(Http500, render(timInstance, "errors.5xx", layout, errorLocal))
        except:
          respond(Http500, "Internal Server Error: " & errMsg)
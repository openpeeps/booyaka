import std/[macros, json, strutils, os,
        sequtils, httpcore, times, options]

import pkg/supranim/support/slug
import pkg/supranim/core/[services, paths]
import pkg/voodoo/language/value
import pkg/[tim, iconim, kapsis/framework]

import pkg/kapsis/interactive/prompts

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
        proc (args: StackView, argc: int): value.Value =
          ## Convert a string to a URL-friendly slug
          return initValue(slugify(args[0].stringVal[]))
        )

      timInstance.userScript.addProc("dashboard", @[paramDef("x", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
          # prefix a link with `/dashboard/`
          return initValue("/dashboard/" & args[0].stringVal[])
        )

      timInstance.userScript.addProc("icon", @[paramDef("name", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
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
            "hasLogo": globalBooyakaConfig.metadata.logo.isSome(),
            "hasNotifications": globalBooyakaConfig.header.notification.isSome()
          }
        }
      timInstance.precompile()

    proc getTimInstance*: TimEngine =
      # Returns the singleton instance of the Tim Engine
      if timInstance == nil:
        raise newException(ValueError, "Tim Engine not initialized")
      return timInstance

  client do:
    template render*(view: string, layout: string = "base",
                      httpCode = Http200, local: JsonNode = nil): untyped =
      ## Renders a Tim template and sends it as an HTTP response.
      ## It must be used within a route handler (controller).
      try:
        let output = render(timInstance, view, layout, local)
        respond(httpCode, output)
      except TimEngineError as e:
        displayError("<services.tim> " & e.msg)
        respond(Http500, render(timInstance, "errors.5xx", layout, data = &*{
          "markdown": {
            "meta": {
              "title": "Page Not Found",
              "description": "The page you are looking for does not exist."
            },
          },
          "config": globalBooyakaConfig
        }))
      except Exception as e:
        displayError("<services.tim> " & e.msg)
        respond(Http500, render(timInstance, "errors.5xx", layout, data = &*{
          "markdown": {
            "meta": {
              "title": "Page Not Found",
              "description": "The page you are looking for does not exist."
            },
          },
          "config": globalBooyakaConfig
        }))
    
    template renderView*(view: string, httpCode = Http200, local: JsonNode = nil): untyped =
      ## Renders a Tim view without a layout and sends it as an HTTP response.
      ## This can be used for rendering partials or standalone views.
      try:
        let output = renderView(timInstance, view, local)
        respond(httpCode, output)
      except TimEngineError as e:
        displayError("<services.tim> " & e.msg)
        respond(Http500, renderView(timInstance, "errors.5xx", data = &*{
          "markdown": {
            "meta": {
              "title": "Page Not Found",
              "description": "The page you are looking for does not exist."
            },
          },
          "config": globalBooyakaConfig
        }))
      except Exception as e:
        displayError("<services.tim> " & e.msg)
        respond(Http500, renderView(timInstance, "errors.5xx", data = &*{
          "markdown": {
            "meta": {
              "title": "Page Not Found",
              "description": "The page you are looking for does not exist."
            },
          },
          "config": globalBooyakaConfig
        }))
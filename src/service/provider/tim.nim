import std/[macros, json, strutils, os,
        sequtils, httpcore, times, options]

import pkg/supranim/support/slug
import pkg/supranim/core/[services, paths]
import pkg/vancode/interpreter/value
import pkg/[tim, iconim, kapsis/framework]

import pkg/kapsis/interactive/prompts

export HttpCode, render, `&*`
export times.now, times.format

import ../../app/structs
import ./assets, ./logger

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
      logger("Service Tim: Initializing Tim Engine (backend + frontend)")
      when defined release:
        timInstance = newTim(globalData = global)
      else:
        timInstance = newTim(globalData = global)
        # timInstance = newTim(
        #   src = src,
        #   output = output,
        #   basePath = basePath,
        #   globalData = global
        # )

      # predefine foreign functions
      timInstance.userScript.addProc("slugify", @[paramDef("s", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
          return initValue(slugify(args[0].stringVal[]))
        )

      timInstance.userScript.addProc("dashboard", @[paramDef("x", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
          return initValue("/dashboard/" & args[0].stringVal[])
        )

      timInstance.userScript.addProc("icon", @[paramDef("name", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
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

      when defined release:
        timInstance.precompile(
          views = staticAssets().directory("views"),
          layouts = staticAssets().directory("layouts"),
          partials = staticAssets().directory("partials"),
        )
      else:
        timInstance.precompile()

    proc getTimInstance*: TimEngine =
      # Returns the singleton instance of the Tim Engine
      if timInstance == nil:
        raise newException(ValueError, "Tim Engine not initialized")
      return timInstance

    proc buildSetup*(src, output, basePath: string; global = newJObject()) =
      echo "  Building Tim Engine templates..."
      when defined release:
        timInstance = newTim(globalData = global)
      else:
        timInstance = newTim(
          src = src,
          output = output,
          basePath = basePath,
          globalData = global
        )
      timInstance.userScript.addProc("slugify", @[paramDef("s", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
          return initValue(slugify(args[0].stringVal[]))
      )
      timInstance.userScript.addProc("dashboard", @[paramDef("x", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
          return initValue("/dashboard/" & args[0].stringVal[])
      )
      timInstance.userScript.addProc("icon", @[paramDef("name", ttyString)], ttyString,
        proc (args: StackView, argc: int): value.Value =
          let iconName = args[0].stringVal[]
          return initValue($icon(iconName))
      )
      when defined release:
        timInstance.precompile(
          views = staticAssets().directory("views"),
          layouts = staticAssets().directory("layouts"),
          partials = staticAssets().directory("partials"),
        )
      else:
        timInstance.precompile()

    proc buildRender*(path: string, local: JsonNode): string =
      if timInstance == nil:
        raise newException(ValueError, "Tim Engine not initialized. Call buildSetup first.")
      var data = newJObject()
      data["path"] = newJString(path)
      data["currentYear"] = newJString(now().format("yyyy"))
      var site = newJObject()
      site["logo"] = newJString(globalBooyakaConfig.metadata.logo.get("/assets/booyaka.png"))
      site["hasLogo"] = newJBool(globalBooyakaConfig.metadata.logo.isSome())
      site["hasNotifications"] = newJBool(globalBooyakaConfig.header.notification.isSome())
      data["site"] = site
      for key, val in local.pairs:
        data[key] = val
      result = render(timInstance, "index", "base", data)

  client do:

    proc error*(message: string, exception: ref Exception) =
      echo message
      echo exception.getStackTrace()

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
        error("error", getCurrentException())
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
        logger("Tim Engine: " & e.msg, ERROR)
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
        logger("Tim Engine: " & e.msg, ERROR)
        error("error", getCurrentException())
        respond(Http500, renderView(timInstance, "errors.5xx", data = &*{
          "markdown": {
            "meta": {
              "title": "Page Not Found",
              "description": "The page you are looking for does not exist."
            },
          },
          "config": globalBooyakaConfig
        }))
      return # blocks further execution in the route handler after rendering the view
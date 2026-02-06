import std/json

import supranim/controller

import ../service/provider/[tim, markdown]

ctrl get4xx:
  ## Renders a 4xx error page
  render("errors.4xx", local = &*{
    "markdown": {
      "meta": {
        "title": "Page Not Found",
        "description": "The page you are looking for does not exist."
      },
    },
    "config": toJson(globalBooyakaConfig).fromJson()
  })
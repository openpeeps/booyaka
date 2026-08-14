#
# This file is automatically imported by the Supranim framework.
# It is used to define the routes for the application.
#

routes:
  get "/"
    # GET route links to `getHomepage` controller

  get "/results.json"
    # GET route links to `getResultsJson` controller

  get "/llms.txt"
    # GET route links to `getLlmsTxt` controller, serving the raw
    # `llms.md` file (if present in the root of the contents directory)
    # as plain text.

  get "/search"
    # GET route links to `getSearch` controller

  get "/{version:semver}/{slug:anySlug}"
    # GET route links to `getVersionSlug` controller, serving a page
    # from a specific documentation version (e.g. `/v1.0.0/install`).

  get "/{version:semver}"
    # GET route links to `getVersion` controller, serving the index
    # page of a specific documentation version (e.g. `/v1.0.0`).

  get "/{slug:anySlug}"
    # A catch-all GET route that will match any path
    # and pass it to the `getSlug` controller for 
    # handling the markdown rendering based on the slug.

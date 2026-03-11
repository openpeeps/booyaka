#
# This file is automatically imported by the Supranim framework.
# It is used to define the routes for the application.
#

routes:
  get "/"
    # GET route links to `getHomepage` controller

  get "/results.json"
    # GET route links to `getResultsJson` controller

  get "/search"
    # GET route links to `getSearch` controller
  
  get "/{slug:anySlug}"
    # A catch-all GET route that will match any path
    # and pass it to the `getSlug` controller for 
    # handling the markdown rendering based on the slug.
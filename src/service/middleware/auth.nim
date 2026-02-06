import pkg/supranim/middleware
import ../provider/session

newMiddleware authenticate:
  ## Checks if the user is authenticated. If not, redirects to the login page.
  withSession do:
    let userData = req.getClientData()
    if userSession.isAuthenticated():
      next() # continue to the next middleware

  abort("/auth/login") # redirects to `GET /auth/login` page

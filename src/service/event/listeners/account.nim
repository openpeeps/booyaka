import std/[options, tables, times]

import pkg/[enimsql, kapsis/cli]
import pkg/supranim/service/events
import pkg/supranim/support/[auth, url, nanoid]
import ../../service/singleton/db

from pkg/supranim/application import appInstance, config

listener "account.password.request":
  ## Event listener for requesting a password reset
  ## link sent to the user email address.
  assert args.isSome()
  {.gcsafe.}:
    withDB do:
      # connect to the database and check if the user exists.
      # if found retrieve user's object
      let dbres =
        Models.table("users")
              .select("id", "pk", "sk")
              .where("email", args.get()[0])
              .get()
      if unlikely(dbres.isEmpty):
        return # no user found with the given email address. abort listener
      let
        user = dbres.first()
        userId = user.get("id").value
      # check if the user has already
      # requested a password reset link and if it's not expired
      let anyPassRequests =
        Models.table("user_account_password_resets")
              .select.where("user_id", userId).getAll()
      if anyPassRequests.isEmpty() == false:
        var hasAnyValidRequests: bool
        for anyPassReq in anyPassRequests:
          # todo enimsql must be able to automatically
          # parse columns with DateTime type
          let expValue = anyPassReq.get("expires_at").value
          let expiresAt: DateTime = times.parse(expValue, "yyyy-MM-dd HH:mm:sszz")
      
          if expiresAt > now():
            # the already generated password reset link is still valid
            # omit the generation of a new password reset link
            hasAnyValidRequests = true
          else:
            # todo move the cleanup of expired password reset links
            # to a queue worker (once implemented)
            Models.table("user_account_password_resets")
                  .remove.where("token", anyPassReq.get("token").value)
                  .exec()
        if hasAnyValidRequests:
          return # the already generated password reset link is still valid

      # otherwise, generate a new password reset link
      # and store it in the database.
      let
        createdAt = now()
        token = boxEncrypt(boxRandomBytes().bin2hex, user.get("pk").value, user.get("sk").value)
        expInterval = appInstance().config("session.settings.expiration_time").getInt
        # default expiration time is 60 minutes.
        # use `config/session.expiration` to customize the expiration time

      # store the password reset link in the database
      # and send it to the user email address.
      Models.table("user_account_password_resets").insert({
        "user_id": userId,
        "token": token,
        "created_at": $(createdAt),
        "expires_at": $(createdAt + minutes(expInterval))
      }).exec()

      when not defined release:
        displayInfo("account.password.request")
        display("generate password reset link:")
        display($link("/auth/reset-password", {"token": token}))

listener "account.register":
  ## Event listener for registering a new user account.
  assert args.isSome()
  {.gcsafe.}:
    withDB do:
      let fields = args.get()
      let anyUser = Models.table("users")
                          .select("id").where("email", fields[0]).get()
      # check if the user already exists
      # if so, abort the registration process
      if anyUser.isEmpty() == false: return
      
      # otherwise, create a new user account
      # and store it in the database.
      let (pk, sk) = auth.boxKeys()
      let userId = Models.table("users").insert({
          "name": "",
          "username": nanoid.generate(size = 32),
          "email": fields[0],
          "pk": pk,
          "sk": sk,
          "password": auth.hashPassword(fields[1]),
          "created_at": $(now())
        }).execGet()

      # generate the confirmation link
      # for the freshly created user account
      # and store it in the database.
      let confirmationLink = auth.boxEncrypt(fields[0], pk, sk)
      Models.table("user_account_confirmations").insert({
        "user_id": $userId,
        "token": confirmationLink,
        "created_at": $(now()),
        "expires_at": $(now() + 10.minutes)
      }).exec()
      
      when not defined release:
        # when not in release mode
        # we'll output the generated user account
        # and the confirmation link to the console
        # this is useful for testing purposes.
        displaySuccess("Created test account:")
        display(span("E-mail:"), green(fields[0]))
        display(span("Password:"), green(fields[1]), span("\n"))

        displayInfo("Confirmation link:")
        display($link("/account/verify", {"token": confirmationLink}))

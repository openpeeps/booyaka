import std/[strutils, tables, times, macros, os]
import pkg/[enimsql, jsony, kapsis/cli]

import pkg/supranim/core/servicemanager
import pkg/supranim/core/[paths, config]
import pkg/supranim/support/[nanoid, auth, url]

initService DB[Global]:
  backend do:
    macro loadModels =
      # auto discover /database/models/*.nim
      # nim files prefixed with `!` will be ignored
      result = newStmtList()
      for fModel in walkDirRec(modelPath):
        let f = fModel.splitFile
        if f.ext == ".nim" and f.name.startsWith("!") == false:
          add result, nnkImportStmt.newTree(newLit(fModel))
          add result, nnkExportStmt.newTree(ident(f.name))
    loadModels() # autoload available models

  client do:
    proc init*() =
      loadEnvStatic()
      enimsql.initdb(
        name = getEnv("database.name"),
        user = getEnv("database.user"),
        password = getEnv("database.password")
      )
      withDB do:
        # create database tables if not exists
        initTable(Users)
        initTable(UserSessions)
        initTable(UserAccountConfirmations)
        initTable(UserAccountEmailConfirmations)
        initTable(UserAccountPasswordResets)

        # the following code is used to
        # create a test user account.
        # this code should be removed in production
        # and should be moved to a seeder
        # or a migration file.
        let userRes =
          Models.table("users")
                .select.where("id", "1").getAll()

        if userRes.isEmpty:
          let (pk, sk) = auth.boxKeys()
          let userId = Models.table("users").insert({
            "name": "Johnny Dope",
            "username": nanoid.generate(size = 32),
            "email": "test@example.com",
            "pk": pk,
            "sk": sk,
            "password": auth.hashPassword("strong password here"),
            "created_at": $(now())
          }).execGet()
          
          displaySuccess("Created test account:")
          display(span("E-mail:"), green("test@example.com"))
          display(span("Password:"), green("strong password here"), span("\n"))

          let confirmationLink = auth.boxEncrypt("test@example.com", pk, sk)
          Models.table("user_account_confirmations").insert({
            "user_id": $userId,
            "token": confirmationLink,
            "created_at": $(now()),
            "expires_at": $(now() + 10.minutes)
          }).exec()
          
          displayInfo("Confirmation link:")
          display($link("/account/verify", {"token": confirmationLink}))
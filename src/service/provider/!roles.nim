# Supranim - A fast MVC web framework
# for building web apps & microservices in Nim.
#
#   (c) 2025 MIT License | Made by Humans from OpenPeeps
#   https://supranim.com | https://github.com/supranim
import pkg/supranim/core/servicemanager
import pkg/libsodium/[sodium, sodium_sizes]

initService UserRoles[Singleton]:
  backend do:
    
    discard
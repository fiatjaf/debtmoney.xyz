module Page exposing (..)

import Route exposing ((:=), static, (</>))


prefix = "/app"

type Page
  = HomePage
  | ThingPage String
  | UserPage String
  | NotFound

homePage = HomePage := static ""
recordPage = ThingPage := static "record" </> Route.string
userPage = UserPage := static "user" </> Route.string

routes = Route.router [homePage, recordPage, userPage]

match : String -> Page
match
  = String.dropLeft (String.length prefix)
  >> Debug.log "navigated to location"
  >> Route.match routes
  >> Debug.log "matched route"
  >> Maybe.withDefault NotFound

module Page exposing (..)

import Route exposing ((:=), static, (</>))


prefix = "/app"

type Page
  = HomePage
  | RecordPage Int
  | UserPage String
  | NotFound

homePage = HomePage := static ""
recordPage = RecordPage := static "record" </> Route.int
userPage = UserPage := static "user" </> Route.string

routes = Route.router [homePage, recordPage, userPage]

match : String -> Page
match
  = String.dropLeft (String.length prefix)
  >> Debug.log "navigated to location"
  >> Route.match routes
  >> Debug.log "matched route"
  >> Maybe.withDefault NotFound

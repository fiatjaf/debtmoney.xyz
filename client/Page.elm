module Page exposing (..)

import Html exposing (Html, text, a)
import Html.Events exposing (onClick)
import Route exposing ((:=), static, (</>))


prefix = "/app"

type Page
  = HomePage
  | ThingPage String
  | UserPage String
  | NotFound

homePage = HomePage := static ""
thingPage = ThingPage := static "thing" </> Route.string
userPage = UserPage := static "user" </> Route.string

routes = Route.router [homePage, thingPage, userPage]

match : String -> Page
match
  = String.dropLeft (String.length prefix)
  >> Debug.log "navigated to location"
  >> Route.match routes
  >> Debug.log "matched route"
  >> Maybe.withDefault NotFound

type GlobalMsg
  = Navigate String

link : String -> String -> Html GlobalMsg
link to name = a [ onClick <| Navigate (prefix ++ to) ] [ text name ]

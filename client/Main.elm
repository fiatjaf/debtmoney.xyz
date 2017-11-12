import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option, header, nav
  , span, section, nav, img, label
  )
import Html.Lazy exposing (lazy, lazy2)
import Html.Attributes exposing (class, href, value)
import Html.Events exposing (onClick, onSubmit, onWithOptions)
import Navigation exposing (Location)
import Task exposing (Task)
import Dict
import Time exposing (Time)
import Result
import Date
import Date.Format
import GraphQL.Client.Http exposing (sendQuery, sendMutation)
import GraphQL.Request.Builder exposing (request)

import Page exposing (..)
import User exposing (..)
import Thing exposing (..)
import Helpers exposing (..)


type alias Flags = {}


main =
  Navigation.programWithFlags
    (.pathname >> Navigate)
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


-- MODEL


type alias Model =
  { me : User.User
  , route : Page
  , user : User
  , thing : Thing
  , newThing : NewThing
  , error : String
  , notification : String
  , loading : String
  }


init : Flags -> Location -> (Model, Cmd Msg)
init flags location =
  let 
    (m, loadmyself) = update LoadMyself
      <| Model
        defaultUser
        HomePage
        defaultUser
        defaultThing
        defaultNewThing
        ""
        ""
        ""
    (nextm, handlelocation) = update (Navigate location.pathname) m
  in
    nextm ! [ loadmyself, handlelocation ]


-- UPDATE


type Msg
  = EraseNotifications
  | Navigate String
  | LoadMyself
  | GotMyself (Result GraphQL.Client.Http.Error User.User)
  | GotUser (Result GraphQL.Client.Http.Error User.User)
  | GotThing (Result GraphQL.Client.Http.Error Thing)
  | NewThingAction NewThingMsg
  | GotNewThingResponse (Result GraphQL.Client.Http.Error Thing)
  | ThingAction String ThingMsg
  | UserAction String UserMsg
  | GotThingConfirmationResponse (Result GraphQL.Client.Http.Error Thing)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    EraseNotifications ->
      ( { model | error = "", loading = "", notification = "" }
      , Cmd.none
      )
    Navigate pathname ->
      let
        route = match pathname
        m = { model | route = route }
        (nextm, effect) = case route of
          HomePage -> update LoadMyself m
          ThingPage thingId ->
            ( { m | loading = "Loading thing..." }
            , request thingId thingQuery
              |> sendQuery "/_graphql"
              |> Task.attempt GotThing
            )
          UserPage userId ->
            ( { m | loading = "Loading " ++ userId ++ "'s profile..." }
            , request userId userQuery
              |> sendQuery "/_graphql"
              |> Task.attempt GotUser
            )
          NotFound -> ( m, Cmd.none)
        updateurl = if route == model.route
          then Cmd.none
          else Navigation.newUrl pathname
      in
        nextm ! [ effect, updateurl ]
    LoadMyself ->
      ( { model | loading = "Loading your profile..." }
      , Cmd.batch
        [ request "me" userQuery
          |> sendQuery "/_graphql"
          |> Task.attempt GotMyself
        , delay (Time.second * 5) EraseNotifications
        ]
      )
    GotMyself result ->
      case result of
        Ok user ->
          ( { model
              | me = user
              , loading = ""
              , newThing = updateNewThing (EnsureParty user.id) model.newThing
            }
          , Cmd.none
          )
        Err err ->
          ( { model | error = errorFormat err, loading = "" }
          , delay (Time.second * 5) EraseNotifications
          )
    GotUser result ->
      case result of
        Ok user -> { model | user = user, loading = "" } ! []
        Err err ->
          ( { model | error = errorFormat err, loading = "" }
          , delay (Time.second * 5) EraseNotifications
          )
    GotThing result ->
      case result of
        Ok thing -> { model | thing = thing, loading = "" } ! []
        Err err ->
          ( { model | error = errorFormat err, loading = "" }
          , delay (Time.second * 5) EraseNotifications
          )
    NewThingAction change ->
      case change of
        Submit -> 
          ( { model | loading = "Submitting transaction..." }
          , request model.newThing newThingMutation
            |> sendMutation "/_graphql"
            |> Task.attempt GotNewThingResponse
          )
        _ ->
          ( { model | newThing = updateNewThing change model.newThing }
          , Cmd.none
          )
    GotNewThingResponse result ->
      case result of
        Ok thing -> update LoadMyself
          { model
            | loading = ""
            , notification = "Saved transaction with id " ++ thing.id
            , newThing = defaultNewThing
          }
        Err err ->
          ( { model | error = errorFormat err, loading = "" }
          , delay (Time.second * 5) EraseNotifications
          )
    ThingAction thingId msg ->
      case msg of
        ConfirmThing ->
          ( { model | loading = "Confirming transaction..." }
          , request thingId confirmThingMutation
            |> sendMutation "/_graphql"
            |> Task.attempt GotThingConfirmationResponse
          )
    UserAction userId msg ->
      case msg of
        UserThingAction thingId msg -> update (ThingAction thingId msg) model
    GotThingConfirmationResponse result ->
      case result of
        Ok thing -> update LoadMyself { model | loading = "" }
        Err err ->
          ( { model | error = errorFormat err, loading = "" }
          , delay (Time.second * 5) EraseNotifications
          )


-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none


-- VIEW


view : Model -> Html Msg
view model =
  div []
    [ nav [ class "navbar" ]
      [ div [ class "navbar-brand" ]
        [ div [ class "navbar-item logo" ] [ text "debtmoney" ]
        , div [ class "navbar-item" ]
          [ div [ class "field" ]
            [ if model.me.id == ""
              then a [ href "/" ] [ text "login" ]
              else text model.me.id
            ]
          ]
        ]
      ]
    , div [ class "section" ]
      [ if model.error == "" then text ""
        else div [ class "notification is-danger" ] [ text <| model.error ]
      , if model.notification == "" then text ""
        else div [ class "notification is-success" ] [ text <| model.notification ]
      , if model.loading == "" then text ""
        else div [ class "pageloader" ]
          [ div [ class "spinner" ] []
          , div [ class "title" ] [ text model.loading ]
          ]
      ]
    , section [ class "section" ]
      [ div [ class "container" ]
        [ case model.route of
          HomePage ->
            Html.map (UserAction model.me.id)
              <| lazy2 viewUser model.me model.me
          ThingPage r ->
            Html.map (ThingAction model.thing.id)
              <| lazy viewThing model.thing
          UserPage u ->
            Html.map (UserAction model.user.id)
              <| lazy2 viewUser model.me model.user
          NotFound ->
            div [] [ text "this page doesn't exist" ]
        ]
      ]
    , section [ class "section" ]
      [ div [ class "container" ]
        [ Html.map NewThingAction ( lazy viewNewThing model.newThing )
        ]
      ]
    ]

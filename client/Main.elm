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
import Http
import Dict
import Array
import Time exposing (Time)
import Process
import Json.Decode as JD
import Json.Encode as JE
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
    (nextm, handlelocation) = update (Navigate location.pathname) m
  in
    nextm ! [ loadmyself, handlelocation ]


-- UPDATE


type Msg
  = EraseError
  | Navigate String
  | LoadMyself
  | GotMyself (Result GraphQL.Client.Http.Error User.User)
  | GotUser (Result GraphQL.Client.Http.Error User.User)
  | GotThing (Result GraphQL.Client.Http.Error Thing)
  | NewThingChange NewThingMsg
  -- | SubmitNewThing
  -- | GotDebtDeclarationResponse (Result GraphQL.Http.Error ServerResult)
  -- | ConfirmThing Int
  -- | GotThingConfirmationResponse (Result Http.Error ServerResult)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    EraseError ->
      ( { model | error = "", loading = "" }
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
      , request "me" userQuery
        |> sendQuery "/_graphql"
        |> Task.attempt GotMyself
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
          ( { model | error = errorFormat err }
          , delay (Time.second * 4) EraseError
          )
    GotUser result ->
      case result of
        Ok user -> { model | user = user, loading = "" } ! []
        Err err ->
          ( { model | error = errorFormat err }
          , delay (Time.second * 4) EraseError
          )
    GotThing result ->
      case result of
        Ok thing -> { model | thing = thing, loading = "" } ! []
        Err err ->
          ( { model | error = errorFormat err }
          , delay (Time.second * 4) EraseError
          )
    NewThingChange change ->
      ( { model | newThing = updateNewThing change model.newThing }
      , Cmd.none
      )
    -- SubmitDebtDeclaration ->
    --   ( { model | loading = "Submitting debt declaration..." }
    --   , submitDebt model GotDebtDeclarationResponse
    --   )
    -- GotDebtDeclarationResponse result ->
    --   case result of
    --     Ok thing -> update LoadMyself { model | loading = "" }
    --     Err err ->
    --       ( { model | error = errorFormat err }
    --       , delay (Time.second * 4) EraseError
    --       )
    -- ConfirmThing thingId ->
    --   ( model
    --   , submitConfirmation thingId GotThingConfirmationResponse
    --   )
    -- GotThingConfirmationResponse result ->
    --   case result of
    --     Ok thing -> update LoadMyself { model | loading = "" }
    --     Err err ->
    --       ( { model | error = errorFormat err }
    --       , delay (Time.second * 4) EraseError
    --       )


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
      [ div [ class "container" ]
        [ if model.error /= ""
          then div [ class "error notification is-danger" ] [ text <| model.error ]
          else if model.loading /= ""
          then div [ class "pageloader" ]
            [ div [ class "spinner" ] []
            , div [ class "title" ] [ text model.loading ]
            ]
          else div [] []
        ]
      ]
    , section [ class "section" ]
      [ div [ class "container" ]
        [ case model.route of
          HomePage -> lazy userView model.me
          ThingPage r -> lazy thingView model.thing
          UserPage u -> lazy userView model.user
          NotFound -> div [] [ text "this page doesn't exists" ]
        ]
      ]
    , section [ class "section" ]
      [ div [ class "container" ]
        [ Html.map NewThingChange ( lazy viewNewThing model.newThing )
        ]
      ]
    ]

-- thingRow : Bool -> String -> Thing.Thing -> Html Msg
-- thingRow itsme userId thing =
--   let 
--     confirm =
--       if itsme
--         then if List.member userId thing.confirmed
--         then text ""
--         else button [ onClick <| ConfirmThing thing.id ] [ text "confirm" ]
--       else text ""
--   in
--     tr []
--       [ td [] [ link ("/thing/" ++ (toString thing.id)) (date thing.date) ]
--       , td [] [ thingDescription thing ]
--       , td []
--         [ table []
--           [ tr []
--             <| confirm ::
--               List.map
--                 (td [] << List.singleton << userLink)
--                 thing.confirmed
--           ]
--         ]
--       ]
-- 
-- thingDescription
--       span []
--         [ span []
--             <| List.map userLink
--             <| Dict.keys bs.parties
--         , text " have paid "
--         , span []
--             <| List.map (\p -> text <| p.paid ++ " of " ++ p.due ++ " due")
--             <| Dict.values bs.parties
--         , text " for "
--         , text bs.object
--         ]

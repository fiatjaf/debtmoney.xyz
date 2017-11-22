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
import Platform.Cmd as Cmd
import Array exposing (Array)
import Time exposing (Time)
import Result
import GraphQL.Client.Http exposing (sendQuery, sendMutation)
import GraphQL.Request.Builder exposing (request)
import Select

import Page exposing (..)
import User exposing (..)
import Thing exposing (..)
import EditingThing exposing (..)
import Helpers exposing (..)


type alias Flags = {}


main =
  Navigation.programWithFlags
    (.pathname >> (GlobalAction << Navigate))
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
  , editingThing : EditingThing
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
        defaultEditingThing
        ""
        ""
        ""
    (nextm, handlelocation) = update (GlobalAction (Navigate location.pathname)) m
  in
    nextm ! [ loadmyself, handlelocation ]


-- UPDATE


type Msg
  = RedirectToLanding
  | EraseNotifications
  | LoadMyself
  | GotMyself (Result GraphQL.Client.Http.Error User.User)
  | GotUser (Result GraphQL.Client.Http.Error User.User)
  | GotThing (Result GraphQL.Client.Http.Error Thing)
  | GotResponse String (Result GraphQL.Client.Http.Error Thing)
  | EditingThingAction EditingThingMsg
  | ThingAction Thing ThingMsg
  | UserAction User UserMsg
  | GlobalAction GlobalMsg
  | Noop

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    RedirectToLanding ->
      ( model
      , Navigation.load "/"
      )
    EraseNotifications ->
      ( { model | error = "", loading = "", notification = "" }
      , Cmd.none
      )
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
              , editingThing = model.editingThing
                |> updateEditingThing (EnsureParty user.id)
                |> updateEditingThing (SetAsset user.default_asset)
            }
          , Cmd.none
          )
        Err err ->
          ( { model | error = errorFormat err, loading = "" }
          , delay (Time.second * 5) RedirectToLanding
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
    EditingThingAction change ->
      let
        ( m, eff ) = case change of
          Submit -> 
            ( { model | loading = "Submitting transaction..." }
            , request model.editingThing setThingMutation
              |> sendMutation "/_graphql"
              |> Task.attempt (GotResponse <| "Saved transaction.")
            )
          Delete ->
            ( { model | loading = "Deleting transaction " ++ model.editingThing.id ++ "..." }
            , request model.editingThing.id deleteThingMutation
              |> sendMutation "/_graphql"
              |> Task.attempt
                (GotResponse <| "Deleted transaction " ++ model.editingThing.id ++ ".")
            )
          UpdateParty index (SelectMsg m) ->
            let
              party = model.editingThing.parties
                |> Array.get index
                |> Maybe.withDefault defaultInputParty
              ( _, cmd ) = Select.update selectConfig m party.selectState
              eff = Cmd.map (UpdateParty index >> EditingThingAction) cmd
            in
              ( model, eff )
          _ -> ( model, Cmd.none )
      in
        ( { model | editingThing = updateEditingThing change model.editingThing }
        , eff
        )
    GotResponse success_message result ->
      case result of
        Ok thing -> update LoadMyself
          { model
            | loading = ""
            , notification = success_message
            , editingThing = defaultEditingThing
          }
        Err err ->
          ( { model | error = errorFormat err, loading = "" }
          , delay (Time.second * 5) EraseNotifications
          )
    ThingAction thing msg ->
      case msg of
        EditThing ->
          ( { model
              | editingThing = EditingThing
                  thing.id
                  thing.actual_date
                  thing.name
                  thing.asset
                  ( if thing.total_due_set then thing.total_due else "" )
                  ( thing.parties
                    |> List.map
                      (\p ->
                        InputParty
                          (if p.user_id /= "" then p.user_id else p.account_name)
                          (if p.due_set then p.due else "")
                          p.paid
                          0
                          defaultInputParty.selectState
                          defaultInputParty.blocked
                      )
                    |> Array.fromList
                  )
            }
          , Cmd.none
          )
        ConfirmThing confirm ->
          ( { model | loading = "Confirming transaction..." }
          , request (thing.id, confirm) confirmThingMutation
            |> sendMutation "/_graphql"
            |> Task.attempt (GotConfirmationResponse >> ThingAction thing)
          )
        PublishThing ->
          ( { model | loading = "Publishing transaction..." }
          , request thing.id publishThingMutation
            |> sendMutation "/_graphql"
            |> Task.attempt (GotConfirmationResponse >> ThingAction thing)
          )
        GotConfirmationResponse result ->
          case result of
            Ok thing -> update LoadMyself { model | loading = "" }
            Err err ->
              ( { model | error = errorFormat err, loading = "" }
              , delay (Time.second * 5) EraseNotifications
              )
        ThingGlobalAction msg -> update (GlobalAction msg) model
    UserAction user msg ->
      case msg of
        UserThingAction thing msg -> update (ThingAction thing msg) model
        UserGlobalAction msg -> update (GlobalAction msg) model
        UserEditingThingAction msg -> update (EditingThingAction msg) model
    GlobalAction msg ->
      case msg of
        Navigate pathname ->
          let route = match pathname
          in
            if route == UserPage model.me.id
            then update (Navigate (prefix ++ "/") |> GlobalAction) model
            else let
              route = match pathname
              m = { model | route = route }
              (nextm, effect) = if route == model.route
                then (m, Cmd.none)
                else case route of
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
    Noop -> ( model, Cmd.none )


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
              else Html.map GlobalAction <| link "/" model.me.id
            ]
          ]
        ]
      ]
    , div []
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
            Html.map (UserAction model.me)
              <| lazy2 viewHome model.me model.editingThing
          ThingPage r ->
            Html.map (ThingAction model.thing)
              <| lazy viewThing model.thing
          UserPage u ->
            Html.map (UserAction model.user)
              <| lazy2 viewUser model.me model.user
          NotFound ->
            div [] [ text "this page doesn't exist" ]
        ]
      ]
    ]

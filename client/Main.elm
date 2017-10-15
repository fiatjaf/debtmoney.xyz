import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option, header, nav
  , span
  )
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit, onWithOptions)
import Navigation exposing (Location)
import Route exposing ((:=), static, (</>))
import Task exposing (Task)
import Http
import Time exposing (Time)
import Process
import Json.Decode as JD
import Json.Encode as JE
import Result
import Date
import Date.Format

import User
import Record exposing (Desc(..))


type alias Flags = {}


prefix = "/app"

main =
  Navigation.programWithFlags
    parseRoute
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


-- ROUTES
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

parseRoute : Location -> Msg
parseRoute = (.pathname) >> Navigate


-- MODEL
type alias Model =
  { me : User.User
  , route : Page
  , user : User.User
  , record : Record.Record
  , declaringDebt : Record.DeclareDebt
  , error : String
  }


init : Flags -> Location -> (Model, Cmd Msg)
init flags location =
  let 
    (m, loadmyself) = update LoadMyself
      <| Model
        User.defaultUser
        HomePage
        User.defaultUser
        Record.defaultRecord
        (Record.DeclareDebt "" "" "0.00")
        ""
    (nextm, handlelocation) = update (Navigate location.pathname) m
  in
    nextm ! [ loadmyself, handlelocation ]


-- UPDATE

type Msg
  = EraseError
  | Navigate String
  | LoadMyself
  | GotMyself (Result Http.Error User.User)
  | GotUser (Result Http.Error User.User)
  | GotRecord (Result Http.Error Record.Record)
  | ChangeDebtCreditor String
  | ChangeDebtAsset String
  | ChangeDebtAmount String
  | SubmitDebtDeclaration
  | GotDebtDeclarationResponse (Result Http.Error ServerResponse)
  | ConfirmRecord Int
  | GotRecordConfirmationResponse (Result Http.Error ServerResponse)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    EraseError ->
      ( {model | error = ""}
      , Cmd.none
      )
    Navigate pathname ->
      let
        route = match pathname
        res = if route == model.route
          then (model, Cmd.none)
          else { model | route = route } !
            [ case route of
              HomePage -> fetchUser "_me" GotMyself
              RecordPage r -> fetchRecord r GotRecord
              UserPage u -> fetchUser u GotUser
              NotFound -> Cmd.none
            , Navigation.newUrl pathname
            ]
      in
        res
          
    LoadMyself ->
      ( model
      , fetchUser "_me" GotMyself
      )
    GotMyself result ->
      case result of
        Ok user -> {model | me = user} ! []
        Err err ->
          ( {model | error = errorFormat err}
          , delay (Time.second * 4) EraseError
          )
    GotUser result ->
      case result of
        Ok user -> {model | user = user} ! []
        Err err ->
          ( {model | error = errorFormat err}
          , delay (Time.second * 4) EraseError
          )
    GotRecord result ->
      case result of
        Ok record -> {model | record = record} ! []
        Err err ->
          ( {model | error = errorFormat err}
          , delay (Time.second * 4) EraseError
          )
    ChangeDebtCreditor x ->
      {model | declaringDebt = model.declaringDebt |> Record.setCreditor x } ! []
    ChangeDebtAsset x ->
      {model | declaringDebt = model.declaringDebt |> Record.setAsset x } ! []
    ChangeDebtAmount x ->
      {model | declaringDebt = model.declaringDebt |> Record.setAmount x } ! []
    SubmitDebtDeclaration ->
      ( model
      , submitDebt model GotDebtDeclarationResponse
      )
    GotDebtDeclarationResponse result ->
      case result of
        Ok record -> update LoadMyself model
        Err err ->
          ( {model | error = errorFormat err}
          , delay (Time.second * 4) EraseError
          )
    ConfirmRecord recordId ->
      ( model
      , submitConfirmation recordId GotRecordConfirmationResponse
      )
    GotRecordConfirmationResponse result ->
      case result of
        Ok record -> update LoadMyself model
        Err err ->
          ( {model | error = errorFormat err}
          , delay (Time.second * 4) EraseError
          )


-- SUBSCRIPTIONS
subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none


-- VIEW

view : Model -> Html Msg
view model =
  div []
    [ header []
      [ if model.error == ""
        then div [] []
        else div [ id "error", class "notification is-danger" ] [ text <| model.error ]
      , if model.me.id == "" then div [] [] else div [ id "me" ]
        [ h1 []
          [ text "hello "
          , meLink model.me.id
          ]
        ]
      ]
    , div []
      [ case model.route of
        HomePage -> userView True model.me
        RecordPage r -> recordView model.me model.record
        UserPage u -> userView (model.user.id == model.me.id) model.user
        NotFound -> div [] [ text "this page doesn't exists" ]
      ]
    ]


userView : Bool -> User.User -> Html Msg
userView itsme user =
  div [ id "user" ]
    [ h1 []
      [ text
        <| (if itsme then "your" else user.id ++ "'s") ++ " profile"
      ]
    , div []
      [ h2 [] [ text "operations:" ]
      , table []
        [ thead []
          [ tr []
            [ th [] [ text "date" ]
            , th [] [ text "description" ]
            , th [] [ text "confirmed" ]
            ]
          ]
        , tbody []
          <| List.map (recordRow itsme user.id) user.records
        ]
      ]
    , div []
      [ h2 [] [ text "address:" ]
      , p [] [ text user.address]
      ]
    , div []
      [ h2 [] [ text "balances:" ]
      , table []
        [ thead []
          [ tr []
            [ th [] [ text "asset" ]
            , th [] [ text "amount" ]
            , th [] [ text "trust limit" ]
            ]
          ]
        , tbody []
          <| List.map assetRow user.balances
        ]
      ]
    , div []
      [ h2 [] [ text "declare a debt" ]
      , input [ type_ "text", onInput ChangeDebtCreditor ] []
      , input [ type_ "text", onInput ChangeDebtAsset ] []
      , input [ type_ "number", step "0.01", onInput ChangeDebtAmount ] []
      , button [ onClick SubmitDebtDeclaration ] [ text "submit" ]
      ]
    ]

recordRow : Bool -> String -> Record.Record -> Html Msg
recordRow itsme userId record =
  let 
    confirm =
      if itsme
        then if List.member userId record.confirmed
        then text ""
        else button [ onClick <| ConfirmRecord record.id ] [ text "confirm" ]
      else text ""
  in
    tr []
      [ td [] [ link ("/record/" ++ (toString record.id)) (date record.date) ]
      , td [] [ recordDescription record ]
      , td []
        [ table []
          [ tr []
            <| confirm ::
              List.map
                (td [] << List.singleton << userLink)
                record.confirmed
          ]
        ]
      ]

date : String -> String
date
  = Date.fromString
  >> Result.withDefault (Date.fromTime 0)
  >> Date.Format.format "%B %e %Y"

recordDescription : Record.Record -> Html Msg
recordDescription record =
  case record.desc of
    Blank -> span [] []
    Debt debt ->
      span []
        [ userLink debt.from
        , text " has borrowed "
        , amount record.asset debt.amount
        , text " from "
        , userLink debt.to
        ]

assetRow : User.Balance -> Html Msg
assetRow balance =
  tr []
    [ td [] [ text balance.asset ]
    , td [] [ text balance.amount ]
    , td [] [ text balance.limit ]
    ]

recordView : User.User -> Record.Record -> Html Msg
recordView me record =
  div [ id "record" ]
    [ h1 [] [ text <| toString record.id ]
    , div [ id "date" ] [ text <| date record.date ]
    , div [ id "description" ] [ recordDescription record ]
    , div [ id "transactions" ]
      [ table []
        <| List.map
            (tr [] << List.singleton << td [] << List.singleton << text)
            record.transactions
      ]
    ]

link : String -> String -> Html Msg
link url display =
  a
    [ onWithOptions "click"
      { stopPropagation = True, preventDefault = True }
      (JD.succeed <| Navigate (prefix ++ url))
    , href <| prefix ++ url
    ] [ text display ]

userLink : String -> Html Msg
userLink userId = link ("/user/" ++ userId) userId

meLink : String -> Html Msg
meLink = link "/"

amount : String -> String -> Html Msg
amount asset amt =
  span [ class "amount" ] [ text <| amt ++ " " ++ asset ]


-- HTTP


fetchUser : String -> (Result Http.Error User.User -> Msg) -> Cmd Msg
fetchUser id hmsg =
  Http.send hmsg <|
    Http.get ("/_/user/" ++ id) User.userDecoder

fetchRecord : Int -> (Result Http.Error Record.Record -> Msg) -> Cmd Msg
fetchRecord id hmsg =
  Http.send hmsg <|
    Http.get ("/_/record/" ++ (toString id)) Record.recordDecoder

submitDebt : Model -> (Result Http.Error ServerResponse -> Msg) -> Cmd Msg
submitDebt model hmsg =
  let
    body = Http.jsonBody <| Record.declareDebtEncoder model.declaringDebt
  in
    Http.send hmsg <|
      Http.post "/_/record/debt" body serverResponseDecoder

submitConfirmation : Int -> (Result Http.Error ServerResponse -> Msg) -> Cmd Msg
submitConfirmation recordId hmsg =
  Http.send hmsg <|
    Http.post
      ("/_/record/" ++ (toString recordId) ++ "/confirm")
      Http.emptyBody
      serverResponseDecoder

errorFormat : Http.Error -> String
errorFormat err =
  case err of
    Http.BadUrl u -> "bad url " ++ u
    Http.Timeout -> "timeout"
    Http.NetworkError -> "network error"
    Http.BadStatus resp ->
      resp.url ++ " returned " ++ (toString resp.status.code) ++ ": " ++ resp.body
    Http.BadPayload x y -> "bad payload (" ++ x ++ ")"

type alias ServerResponse =
  { ok : Bool
  }

serverResponseDecoder : JD.Decoder ServerResponse
serverResponseDecoder = JD.map ServerResponse <| JD.field "ok" JD.bool


-- HELPERS

delay : Time -> msg -> Cmd msg
delay time msg =
  Process.sleep time
    |> Task.andThen (always <| Task.succeed msg)
    |> Task.perform identity

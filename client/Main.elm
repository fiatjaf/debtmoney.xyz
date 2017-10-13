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
        (Record.DeclareDebt "" "" "0.00")
        ""
    (nextm, handlelocation) = update (Navigate location.pathname) m
  in
    nextm ! [ loadmyself, handlelocation ]


-- UPDATE

type Msg
  = Navigate String
  | LoadMyself
  | GotMyself (Result Http.Error User.User)
  | GotUser (Result Http.Error User.User)
  | TypeDebtCreditor String
  | TypeDebtAsset String
  | TypeDebtAmount String
  | SubmitDebtDeclaration
  | GotDebtDeclarationResponse (Result Http.Error ServerResponse)
  | ConfirmRecord Int
  | GotRecordConfirmationResponse (Result Http.Error ServerResponse)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Navigate pathname ->
      let
        route = match pathname
        res = if route == model.route
          then (model, Cmd.none)
          else { model | route = route } !
            [ case route of
              HomePage -> fetchUser "_me" |> Http.send GotMyself
              RecordPage r -> Cmd.none
              UserPage u -> fetchUser u |> Http.send GotUser
              NotFound -> Cmd.none
            , Navigation.newUrl pathname
            ]
      in
        res
          
    LoadMyself ->
      ( model
      , fetchUser "_me" |> Http.send GotMyself
      )
    GotMyself result ->
      case result of
        Ok user ->
          {model | me = user} ! []
        Err err ->
          {model | error = errorFormat err} ! []
    GotUser result ->
      case result of
        Ok user ->
          {model | user = user} ! []
        Err err ->
          {model | error = errorFormat err} ! []
    TypeDebtCreditor x ->
      {model | declaringDebt = model.declaringDebt |> Record.setCreditor x } ! []
    TypeDebtAsset x ->
      {model | declaringDebt = model.declaringDebt |> Record.setAsset x } ! []
    TypeDebtAmount x ->
      {model | declaringDebt = model.declaringDebt |> Record.setAmount x } ! []
    SubmitDebtDeclaration ->
      ( model
      , submitDebt model |> Http.send GotDebtDeclarationResponse
      )
    GotDebtDeclarationResponse result ->
      update LoadMyself model
    ConfirmRecord recordId ->
      ( model
      , submitConfirmation recordId |> Http.send GotRecordConfirmationResponse
      )
    GotRecordConfirmationResponse result ->
      update LoadMyself model


-- SUBSCRIPTIONS
subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none


-- VIEW

view : Model -> Html Msg
view model =
  div []
    [ header []
      [ if model.error == "" then div [] [] else  div [ id "notification" ]
        [ text <| "error: " ++ model.error
        ]
      , if model.me.id == "" then div [] [] else div [ id "me" ]
        [ h1 []
          [ text "hello "
          , melink model.me.id
          ]
        ]
      ]
    , div []
      [ case model.route of
        HomePage -> userView True model.me
        RecordPage r -> div [] []
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
            , th [] [ text "transactions" ]
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
      , input [ type_ "text", onInput TypeDebtCreditor ] []
      , input [ type_ "text", onInput TypeDebtAsset ] []
      , input [ type_ "number", step "0.01", onInput TypeDebtAmount ] []
      , button [ onClick SubmitDebtDeclaration ] [ text "submit" ]
      ]
    ]

recordRow : Bool -> String -> Record.Record -> Html Msg
recordRow itsme userId record =
  let 
    date = Date.fromString
      >> Result.withDefault (Date.fromTime 0)
      >> Date.Format.format "%B %e %Y"
    confirm =
      if itsme
        then if List.member userId record.confirmed
        then text ""
        else button [ onClick <| ConfirmRecord record.id ] [ text "confirm" ]
      else text ""
  in
    tr []
      [ td [] [ text <| date record.date ]
      , td []
        [ case record.desc of
          Debt debt ->
            span []
              [ userlink debt.from
              , text " has borrowed "
              , amount record.asset debt.amount
              , text " from "
              , userlink debt.to
              ]
        ]
      , td []
        [ table []
          [ tr []
            <| confirm ::
              List.map
                (td [] << List.singleton << userlink)
                record.confirmed
          ]
        ]
      , td []
        [ table []
          <| List.map
              (tr [] << List.singleton << td [] << List.singleton << text)
              record.transactions
        ]
      ]

assetRow : User.Balance -> Html Msg
assetRow balance =
  tr []
    [ td [] [ text balance.asset ]
    , td [] [ text balance.amount ]
    , td [] [ text balance.limit ]
    ]

userlink : String -> Html Msg
userlink userId =
  a
    [ class "userlink"
    , onWithOptions
      "click"
      { stopPropagation = True, preventDefault = True }
      (JD.succeed <| Navigate (prefix ++ "/user/" ++ userId))
    , href <| prefix ++ "/user/" ++ userId
    ] [ text userId ]

melink : String -> Html Msg
melink userId =
  a
    [ class "userlink me"
    , onWithOptions
      "click"
      { stopPropagation = True, preventDefault = True }
      (JD.succeed <| Navigate (prefix ++ "/"))
    , href <| prefix ++ "/"
    ] [ text userId ]

amount : String -> String -> Html Msg
amount asset amt =
  span [ class "amount" ] [ text <| amt ++ " " ++ asset ]


-- HTTP


fetchUser : String -> Http.Request User.User
fetchUser id =
  Http.get ("/_/user/" ++ id) User.userDecoder

submitDebt : Model -> Http.Request ServerResponse
submitDebt model =
  let
    body = Http.jsonBody <| Record.declareDebtEncoder model.declaringDebt
  in
    Http.post "/_/debt" body serverResponseDecoder

submitConfirmation : Int -> Http.Request ServerResponse
submitConfirmation recordId =
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

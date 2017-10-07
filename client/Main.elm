import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option
  )
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Task exposing (Task)
import Http
import Json.Decode as JD
import Json.Encode as JE

import User
import Record exposing (Desc(..))


type alias Flags = {}


main =
  Html.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


-- MODEL
type alias Model =
  { user : User.User
  , declaringDebt : Record.DeclareDebt
  , error : String
  }


init : Flags -> (Model, Cmd Msg)
init flags =
  ( Model
    User.defaultUser
    (Record.DeclareDebt "" "" "0.00")
    ""
  , fetchUser "_me" |> Http.send GotMyself)


-- UPDATE

type Msg
  = GotMyself (Result Http.Error User.User)
  | TypeDebtCreditor String
  | TypeDebtAsset String
  | TypeDebtAmount String
  | SubmitDebtDeclaration
  | GotDebtDeclarationResponse (Result Http.Error ServerResponse)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    GotMyself result ->
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
      model !
        [ submitDebt model |> Http.send GotDebtDeclarationResponse
        ]
    GotDebtDeclarationResponse result ->
      model ! []


-- SUBSCRIPTIONS
subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none


-- VIEW

view : Model -> Html Msg
view model =
  div []
    [ if model.error == "" then div [] [] else  div [ id "notification" ]
      [ text <| "error: " ++ model.error
      ]
    , if model.user.id == "" then div [] [] else div [ id "me" ]
      [ h1 [] [ text ("hello " ++ model.user.id) ]
      , div []
        [ h2 [] [ text "your operations:" ]
        , table []
          [ thead []
            [ tr []
              [ th [] [ text "date" ]
              , th [] [ text "kind" ]
              , th [] [ text "description" ]
              , th [] [ text "confirmed" ]
              , th [] [ text "transactions" ]
              ]
            ]
          , tbody []
            <| List.map recordRow model.user.records
          ]
        ]
      , div []
        [ h2 [] [ text "your address:" ]
        , p [] [ text model.user.address]
        ]
      , div []
        [ h2 [] [ text "your balances:" ]
        , table []
          [ thead []
            [ tr []
              [ th [] [ text "asset" ]
              , th [] [ text "amount" ]
              ]
            ]
          , tbody []
            <| List.map assetRow model.user.balances
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
    ]

recordRow : Record.Record -> Html Msg
recordRow record =
  tr []
    [ td [] [ text record.date ]
    , td [] [ text record.kind ]
    , td []
      [ case record.desc of
        Debt debt ->
          text <|
            debt.from ++ " has borrowed " ++ debt.amount ++ " " ++
            record.asset ++ " from " ++ debt.to
      ]
    , td []
      [ table []
        [ tr [] <|
          List.map
            (\confirmed -> td [] [ text confirmed ])
            record.confirmed
        ]
      ]
    , td []
      [ table []
        <| List.map
            (\txn -> tr [] [ td [] [ text txn ] ])
            record.transactions
      ]
    ]

assetRow : User.Balance -> Html Msg
assetRow balance =
  tr []
    [ td [] [ text balance.asset ]
    , td [] [ text balance.amount ]
    ]


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

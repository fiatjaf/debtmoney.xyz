import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option
  )
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Task exposing (Task)
import GraphQL.Client.Http

import Ports
import GraphQL as GQL
import Types exposing (..)


type alias Flags =
  { authSignature : String
  }

main =
  Html.programWithFlags
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


-- MODEL
type alias Model =
  { account : Account
  , authSignature : String
  , declaringDebt : DeclareDebt
  }


init : Flags -> (Model, Cmd Msg)
init flags =
  ( Model
    (Account "" "" "" [])
    flags.authSignature
    (DeclareDebt "" "" "0.00")
  , GQL.q flags.authSignature GQL.myself |> Task.attempt GotAuth)


-- UPDATE

type Msg
  = TypeAuthMessage String
  | SubmitAuthMessage
  | GotAuth (Result GraphQL.Client.Http.Error Account)
  | TypeDebtCreditor String
  | TypeDebtAsset String
  | TypeDebtAmount String
  | SubmitDebtDeclaration
  | GotDebtDeclarationResponse (Result GraphQL.Client.Http.Error ResultType)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    TypeAuthMessage x ->
      {model | authSignature = x} ! []
      
    SubmitAuthMessage ->
      model ! [ GQL.q model.authSignature GQL.myself |> Task.attempt GotAuth ]
    GotAuth result ->
      case result of
        Ok acc ->
          {model | account = acc} !
            [ Ports.saveSignature model.authSignature
            ]
        Err err ->
          (model, Cmd.none)
    TypeDebtCreditor x ->
      {model | declaringDebt = model.declaringDebt |> setCreditor x } ! []
    TypeDebtAsset x ->
      {model | declaringDebt = model.declaringDebt |> setAsset x } ! []
    TypeDebtAmount x ->
      {model | declaringDebt = model.declaringDebt |> setAmount x } ! []
    SubmitDebtDeclaration ->
      model !
        [ ( GQL.m model.authSignature (GQL.declareDebt model.declaringDebt) )
          |> Task.attempt GotDebtDeclarationResponse
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
    [ if model.account.name /= "" then div [] [] else div [ id "login" ]
      [ h1 []
        [ text "Log in with "
        , a [ target "_blank", href "https://keybase.io/sign" ] [ text "Keybase" ]
        ]
      , p [ title "If you're doing it on the CLI your must do a \"clearsign\" (-c)."
        ] [ text "Sign your Keybase username and paste here." ]
      , textarea
        [ onInput TypeAuthMessage
        , placeholder "-----BEGIN PGP SIGNED MESSAGE-----"
        ] []
      , button [ onClick SubmitAuthMessage] [ text "login" ]
      ]
    , if model.account.name == "" then div [] [] else div [ id "me" ]
      [ h1 [] [ text ("hello " ++ model.account.name) ]
      , div []
        [ h2 [] [ text "your address:" ]
        , p [] [ text model.account.public ]
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
            <| List.map assetRow model.account.balances
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

assetRow : Balance -> Html Msg
assetRow balance =
  tr []
    [ td [] [ text balance.asset ]
    , td [] [ text balance.amount ]
    ]

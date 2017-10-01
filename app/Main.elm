import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option
  )
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Task exposing (Task)
import GraphQL.Client.Http

import GraphQL as GQL
import User
import Record


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
  , GQL.q User.myself |> Task.attempt GotMyself)


-- UPDATE

type Msg
  = GotMyself (Result GraphQL.Client.Http.Error User.User)
  | TypeDebtCreditor String
  | TypeDebtAsset String
  | TypeDebtAmount String
  | SubmitDebtDeclaration
  | GotDebtDeclarationResponse (Result GraphQL.Client.Http.Error GQL.Result)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    GotMyself result ->
      case result of
        Ok user ->
          {model | user = user} ! []
        Err err ->
          {model | error = GQL.errorFormat err} ! []
    TypeDebtCreditor x ->
      {model | declaringDebt = model.declaringDebt |> Record.setCreditor x } ! []
    TypeDebtAsset x ->
      {model | declaringDebt = model.declaringDebt |> Record.setAsset x } ! []
    TypeDebtAmount x ->
      {model | declaringDebt = model.declaringDebt |> Record.setAmount x } ! []
    SubmitDebtDeclaration ->
      model !
        [ ( GQL.m (Record.declareDebt model.declaringDebt) )
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
    [ if model.error == "" then div [] [] else  div [ id "notification" ]
      [ text model.error
      ]
    , if model.user.id == "" then div [] [] else div [ id "me" ]
      [ h1 [] [ text ("hello " ++ model.user.id) ]
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

assetRow : User.Balance -> Html Msg
assetRow balance =
  tr []
    [ td [] [ text balance.asset ]
    , td [] [ text balance.amount ]
    ]

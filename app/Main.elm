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
import Types exposing (..)


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
  { user : User
  , declaringDebt : DeclareDebt
  }


init : Flags -> (Model, Cmd Msg)
init flags =
  ( Model
    (User "" "" [])
    (DeclareDebt "" "" "0.00")
  , GQL.q GQL.myself |> Task.attempt GotAuth)


-- UPDATE

type Msg
  = GotAuth (Result GraphQL.Client.Http.Error User)
  | TypeDebtCreditor String
  | TypeDebtAsset String
  | TypeDebtAmount String
  | SubmitDebtDeclaration
  | GotDebtDeclarationResponse (Result GraphQL.Client.Http.Error ResultType)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    GotAuth result ->
      case result of
        Ok user ->
          {model | user = user} ! []
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
        [ ( GQL.m (GQL.declareDebt model.declaringDebt) )
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
    [ if model.user.id == "" then div [] [] else div [ id "me" ]
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

assetRow : Balance -> Html Msg
assetRow balance =
  tr []
    [ td [] [ text balance.asset ]
    , td [] [ text balance.amount ]
    ]

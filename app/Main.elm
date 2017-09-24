import Html exposing (Html, h1, div, textarea, button, p, a, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Task exposing (Task)
import GraphQL.Client.Http

import Ports
import GraphQL exposing (..)
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
  { user : User
  , authSignature : String
  }


init : Flags -> (Model, Cmd Msg)
init flags =
  ( Model (User "") flags.authSignature
  , graphql flags.authSignature myselfRequest |> Task.attempt GotAuth)


-- UPDATE

type Msg
  = TypeAuthMessage String
  | SubmitAuthMessage
  | GotAuth (Result GraphQL.Client.Http.Error User)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    TypeAuthMessage x ->
      ({model | authSignature = x}, Cmd.none)
    SubmitAuthMessage ->
      (model, graphql model.authSignature myselfRequest |> Task.attempt GotAuth)
    GotAuth result ->
      case result of
        Ok user ->
          {model | user = user} !
            [ Ports.saveSignature model.authSignature
            ]
        Err err ->
          (model, Cmd.none)


-- SUBSCRIPTIONS
subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none


-- VIEW

view : Model -> Html Msg
view model =
  div []
    [ if model.user.name /= "" then div [] [] else div [ id "login" ]
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
    , div [ id "me" ] (
      if model.user.name == "" then
        []
      else
        [ text ("hello " ++ model.user.name) ]
    )
    ]

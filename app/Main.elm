import Html exposing (Html, button, div, textarea, text)
import Html.Events exposing (onClick, onInput)
import Http exposing (header)
import GraphQL.Request.Builder exposing (..)
import GraphQL.Client.Http as GraphQLClient
import Task exposing (Task)
import Result
import Base64


main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


-- MODEL

type alias Model =
  { user : User
  , authMessage : String
  }

type alias User =
  { name : String
  }

init : (Model, Cmd Msg)
init =
  (Model (User "") "", Cmd.none)


-- UPDATE

type Msg
  = TypeAuthMessage String
  | SubmitAuthMessage
  | GotAuth (Result GraphQLClient.Error User)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    TypeAuthMessage x ->
      ({model | authMessage = x}, Cmd.none)
    SubmitAuthMessage ->
      (model, graphql model myselfRequest |> Task.attempt GotAuth)
    GotAuth result ->
      case result of
        Ok user ->
          ({model | user = user}, Cmd.none)
        Err err ->
          (model, Cmd.none)


-- HELPERS

graphql : Model -> Request Query a -> Task GraphQLClient.Error a
graphql model request =
  let
    reqOpts =
      { method = "POST"
      , headers =
        [ (header "Authorization" (Base64.encode model.authMessage))
        ]
      , url = "/_graphql"
      , timeout = Nothing
      , withCredentials = False
      }
  in
    GraphQLClient.customSendQuery reqOpts request

myselfRequest : Request Query User
myselfRequest =
  extract
    (field "me"
      []
      (object User
        |> with (field "name" [] string)
      )
    )
    |> queryDocument
    |> request {}


-- SUBSCRIPTIONS
subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none


-- VIEW

view : Model -> Html Msg
view model =
  div []
    [ textarea [onInput TypeAuthMessage] []
    , button [ onClick SubmitAuthMessage] [ text "login" ]
    ]

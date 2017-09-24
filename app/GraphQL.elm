module GraphQL exposing (r, myself)

import Task exposing (Task)
import Http exposing (header)
import Result
import GraphQL.Request.Builder exposing
  ( Request, Query, queryDocument, request
  , with, extract, field
  , object, string, list, int
  )
import GraphQL.Client.Http as GraphQLClient
import Base64

import Types exposing (..)


myself : Request Query User
myself =
  extract
    (field "me"
      []
      (object User
        |> with (field "name" [] string)
        |> with (field "balances" [] <| list
          (object Balance
            |> with (field "asset" [] string)
            |> with (field "amount" [] int)
          )
        )
      )
    )
    |> queryDocument
    |> request {}


r : String -> Request Query a -> Task GraphQLClient.Error a
r authSignature request =
  let
    reqOpts =
      { method = "POST"
      , headers =
        [ (header "Authorization" (Base64.encode authSignature))
        ]
      , url = "/_graphql"
      , timeout = Nothing
      , withCredentials = False
      }
  in
    GraphQLClient.customSendQuery reqOpts request

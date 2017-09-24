module GraphQL exposing (graphql, myselfRequest)

import Task exposing (Task)
import Http exposing (header)
import Result
import GraphQL.Request.Builder exposing
  ( Request, Query, queryDocument, request
  , with, extract, field
  , object, string
  )
import GraphQL.Client.Http as GraphQLClient
import Base64

import Types exposing (..)


graphql : String -> Request Query a -> Task GraphQLClient.Error a
graphql authSignature request =
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

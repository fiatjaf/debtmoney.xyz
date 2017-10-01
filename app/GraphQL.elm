module GraphQL exposing (q, m, Result, errorFormat)

import Task exposing (Task)
import List
import String
import Http

import GraphQL.Request.Builder exposing
  ( Request, Query, Mutation
  , mutationDocument, queryDocument, request
  , with, extract, field
  , object, string, list, int, bool
  )
import GraphQL.Client.Http

q : Request Query a -> Task GraphQL.Client.Http.Error a
q request =
  GraphQL.Client.Http.customSendQuery reqOpts request

m : Request Mutation a -> Task GraphQL.Client.Http.Error a
m request =
  GraphQL.Client.Http.customSendMutation reqOpts request

reqOpts = 
  { method = "POST"
  , headers = []
  , url = "/_graphql"
  , timeout = Nothing
  , withCredentials = False
  }

type alias Result =
  { ok : Bool
  , value : String
  , error : String
  }

errorFormat : GraphQL.Client.Http.Error -> String
errorFormat err =
  case err of
    GraphQL.Client.Http.GraphQLError gqlerrors ->
      List.map .message gqlerrors |> String.join "\n"
    GraphQL.Client.Http.HttpError httperr ->
      case httperr of
        Http.BadUrl u -> "bad url " ++ u
        Http.Timeout -> "timeout"
        Http.NetworkError -> "network error"
        Http.BadStatus resp ->
          resp.url ++ " returned " ++ (toString resp.status.code) ++ ": " ++ resp.body
        Http.BadPayload _ _ -> "bad payload"

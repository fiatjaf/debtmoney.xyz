module GraphQL exposing (q, m, myself, declareDebt)

import Task exposing (Task)
import Http exposing (header)
import Result
import GraphQL.Request.Builder.Variable as Var
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder exposing
  ( Request, Query, Mutation
  , mutationDocument, queryDocument, request
  , with, extract, field
  , object, string, list, int, bool
  )
import GraphQL.Client.Http as GraphQLClient
import Base64

import Types exposing (..)


myself : Request Query Account
myself =
  extract
    (field "me"
      []
      (object Account
        |> with (field "name" [] string)
        |> with (field "source" [] string)
        |> with (field "public" [] string)
        |> with (field "balances" [] <| list
          (object Balance
            |> with (field "asset" [] string)
            |> with (field "amount" [] string)
          )
        )
      )
    )
    |> queryDocument
    |> request {}


declareDebt : DeclareDebt -> Request Mutation ResultType
declareDebt vars =
  let 
    creditorVar = Var.required "creditor" .creditor Var.string
    assetVar = Var.required "asset" .asset Var.string
    amountVar = Var.required "amount" .amount Var.string
  in
    extract
      (field "declareDebt"
        [ ( "creditor", Arg.variable creditorVar )
        , ( "asset", Arg.variable assetVar )
        , ( "amount", Arg.variable amountVar )
        ]
        (object ResultType
          |> with (field "ok" [] bool)
          |> with (field "value" [] string)
          |> with (field "error" [] string)
        )
      )
      |> mutationDocument
      |> request vars


q : String -> Request Query a -> Task GraphQLClient.Error a
q authSignature request =
  let
    o = { reqOpts | headers = [ (header "Authorization" (Base64.encode authSignature)) ] }
  in
    GraphQLClient.customSendQuery o request

m : String -> Request Mutation a -> Task GraphQLClient.Error a
m authSignature request =
  let
    o = { reqOpts | headers = [ (header "Authorization" (Base64.encode authSignature)) ] }
  in
    GraphQLClient.customSendMutation o request

reqOpts = 
  { method = "POST"
  , headers = []
  , url = "/_graphql"
  , timeout = Nothing
  , withCredentials = False
  }

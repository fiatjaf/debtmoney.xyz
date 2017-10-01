module Record exposing (DeclareDebt, setCreditor, setAsset, setAmount, declareDebt)

import GraphQL.Request.Builder.Variable as Var
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder exposing
  ( Request, Query, Mutation
  , mutationDocument, queryDocument, request
  , with, extract, field
  , object, string, list, int, bool
  )
import GraphQL.Client.Http as GraphQLClient

import GraphQL as GQL


type alias DeclareDebt =
  { creditor : String
  , asset : String
  , amount : String
  }

setCreditor x dd = { dd | creditor = x } 
setAsset x dd = { dd | asset = x } 
setAmount x dd = { dd | amount = x } 


declareDebt : DeclareDebt -> Request Mutation GQL.Result
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
        (object GQL.Result
          |> with (field "ok" [] bool)
          |> with (field "value" [] string)
          |> with (field "error" [] string)
        )
      )
      |> mutationDocument
      |> request vars

module User exposing (User, Balance, user, myself, defaultUser)

import GraphQL.Request.Builder.Variable as Var
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder exposing
  ( Request, Query, Mutation
  , mutationDocument, queryDocument, request
  , with, extract, field
  , object, string, list, int, bool
  )
import GraphQL.Client.Http as GraphQLClient

type alias User =
  { id : String
  , address : String
  , balances : List Balance
  }

type alias Balance =
  { asset : String
  , amount : String
  }

defaultUser : User
defaultUser = User "" "" []


myself : Request Query User
myself = user <| {defaultUser | id = "me"}


user : User -> Request Query User
user user =
  extract
    (field "user"
      [ ( "id", Arg.variable <| Var.required "id" .id Var.string )
      ]
      (object User
        |> with (field "id" [] string)
        |> with (field "address" [] string)
        |> with (field "balances" [] <| list
          (object Balance
            |> with (field "asset" [] string)
            |> with (field "amount" [] string)
          )
        )
      )
    )
    |> queryDocument
    |> request user

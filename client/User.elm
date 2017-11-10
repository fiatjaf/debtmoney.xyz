module User exposing (..)

import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var

import Helpers exposing (..)
import Thing exposing (..)


type alias User =
  { id : String
  , address : String
  , balances : List Balance
  , things : List Thing
  }

type alias Balance =
  { asset : String
  , amount : String
  , limit : String
  }

defaultUser : User
defaultUser = User "" "" [] []

userQuery : Document Query User String
userQuery =
  extract
    ( field "user"
      [ ( "id", Arg.variable <| Var.required "id" identity Var.string )
      ]
      userSpec
    )
    |> queryDocument

userSpec = object User
  |> with ( field "id" [] string )
  |> with ( field "address" [] string )
  |> with ( field "balances" [] (list balanceSpec) )
  |> with ( field "things" [] (list thingSpec) )

balanceSpec = object Balance
  |> with ( field "asset" [] string )
  |> with ( field "amount" [] string )
  |> with ( field "limit" [] string )

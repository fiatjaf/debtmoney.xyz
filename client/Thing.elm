module Thing exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option, header, nav
  , span, section, nav, img, label
  )
import Html.Attributes exposing (class)
import Html.Events exposing (onClick, onInput, onSubmit, onWithOptions)
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var

import Helpers exposing (..)

type alias Thing =
  { id : String
  , created_at : String
  , thing_date : String
  , name : String
  , txn : String
  , parties : List Party
  }

defaultThing = Thing "" "" "" "" "" []

type alias Party =
  { user_id : String
  , thing_id : String
  , paid : String
  , due : String
  , confirmed : Bool
  , registered : Bool
  }

thingQuery : Document Query Thing String
thingQuery =
  extract
    ( field "thing"
      [ ( "id", Arg.variable <| Var.required "id" identity Var.string )
      ]
      thingSpec
    )
    |> queryDocument

thingSpec = object Thing
  |> with ( field "id" [] string )
  |> with ( field "created_at" [] string )
  |> with ( field "thing_date" [] string )
  |> with ( field "name" [] string )
  |> with ( field "txn" [] string )
  |> with ( field "parties" [] (list partySpec) )

partySpec = object Party
  |> with ( field "user_id" [] string )
  |> with ( field "thing_id" [] string )
  |> with ( field "paid" [] string )
  |> with ( field "due" [] string )
  |> with ( field "confirmed" [] bool )
  |> with ( field "registered" [] bool )


type alias CreateThingVars =
  { thing_date : String 
  , name : String
  , asset : String
  , parties : List Party
  }

createThing : Document Mutation ServerResult CreateThingVars
createThing =
  extract
    ( field "createThing"
      [ ( "thing_date", Arg.variable <| Var.required "thing_date" .thing_date Var.string )
      , ( "name", Arg.variable <| Var.required "name" .name Var.string )
      , ( "asset", Arg.variable <| Var.required "asset" .asset Var.string )
      , ( "parties", Arg.variable <| Var.required "parties" .parties
          ( Var.list
            ( Var.object "partyType"
              [ Var.field "user_id" .user_id Var.string
              , Var.field "paid" .paid Var.string
              , Var.field "due" .due Var.string
              ]
            )
          )
        )
      ]
      serverResultSpec
    )
    |> mutationDocument


-- VIEWS


thingView : Thing -> Html msg
thingView thing =
  div [ class "thing" ]
    [ h1 [ class "title is-4" ] [ text thing.id ]
    , div [ class "date" ] [ text <| date thing.thing_date ]
    , div [ class "name" ] [ text thing.name ]
    , div [ class "txn" ] [ text thing.txn ]
    ]

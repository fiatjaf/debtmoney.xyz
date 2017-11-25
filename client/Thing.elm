module Thing exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , strong
  , table, tbody, thead, tr, th, td, tfoot
  , input, select, option, header, nav
  , span, section, nav, img, label
  )
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2, lazy3)
import Html.Attributes exposing (class, value, colspan, href, target, classList)
import Html.Events exposing (onInput, onClick, on)
import Maybe exposing (withDefault)
import Json.Decode as J
import Array exposing (Array)
import Decimal exposing (Decimal, zero, add, mul, fastdiv, sub, eq)
import GraphQL.Client.Http
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var
import Tuple exposing (..)
import Prelude exposing (..)
import String exposing (trim)
import String.Extra exposing (nonEmpty, isBlank)

import Helpers exposing (..)
import Page exposing (link, GlobalMsg(..))
import Data.Currencies


-- MODEL


type alias Thing =
  { id : String
  , created_at : String
  , actual_date : String
  , created_by : String
  , name : String
  , asset : String
  , total_due : String
  , total_due_set : Bool
  , txn : String
  , parties : List Party
  , publishable : Bool
  }

defaultThing = Thing "" "" "" "" "" "" "" False "" [] False

type alias Party =
  { thing_id : String
  , user_id : String
  , account_name : String
  , due : String
  , due_set : Bool
  , paid : String
  , note : String
  , added_by : String
  , confirmed : Bool
  }

defaultParty = Party "" "" "" "" False "" "" "" False

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
  |> with ( field "actual_date" [] string )
  |> with ( field "created_by" [] string )
  |> with ( field "name" [] (map (withDefault "") (nullable string)) )
  |> with ( field "asset" [] string )
  |> with ( field "total_due" [] string )
  |> with ( field "total_due_set" [] bool )
  |> with ( field "txn" [] (map (withDefault "") (nullable string)) )
  |> with ( field "parties" [] (list partySpec) )
  |> with ( field "publishable" [] bool )

partySpec = object Party
  |> with ( field "thing_id" [] string )
  |> with ( field "user_id" [] string )
  |> with ( field "account_name" [] string )
  |> with ( field "due" [] string )
  |> with ( field "due_set" [] bool )
  |> with ( field "paid" [] string )
  |> with ( field "note" [] (map (withDefault "") (nullable string)) )
  |> with ( field "added_by" [] string )
  |> with ( field "confirmed" [] bool )

deleteThingMutation : Document Mutation ServerResult String
deleteThingMutation =
  extract
    ( field "deleteThing"
      [ ( "thingId" , Arg.variable <| Var.required "id" identity Var.string )
      ]
      serverResultSpec
    )
    |> mutationDocument

publishThingMutation : Document Mutation ServerResult String
publishThingMutation =
  extract
    ( field "publishThing"
      [ ( "thing_id", Arg.variable <| Var.required "thing_id" identity Var.string )
      ]
      serverResultSpec
    )
    |> mutationDocument

confirmThingMutation : Document Mutation ServerResult (String, Bool)
confirmThingMutation =
  extract
    ( field "confirmThing"
      [ ( "thing_id", Arg.variable <| Var.required "thing_id" first Var.string )
      , ( "confirm", Arg.variable <| Var.required "confirm" second Var.bool )
      ]
      serverResultSpec
    )
    |> mutationDocument


-- UPDATE

type ThingMsg
  = EditThing
  | ConfirmThing Bool
  | PublishThing
  | ThingGlobalAction GlobalMsg

-- VIEW


viewThing : Thing -> Html msg
viewThing thing =
  div [ class "thing" ]
    [ h1 [ class "title is-4" ] [ text thing.id ]
    , div [ class "date" ] [ text <| date thing.actual_date ]
    , div [ class "name" ] [ text thing.name ]
    , div [ class "txn" ] [ text thing.txn ]
    ]


viewThingCard : String -> String -> Thing -> Html ThingMsg
viewThingCard myId userId thing =
  let 
    is_confirmed = thing.parties
      |> List.filter (\p -> ((p.user_id) == myId) && p.confirmed)
      |> List.length
      |> (<) 0

    totaldue = Decimal.fromString thing.total_due |> withDefault zero
    setduesum = thing.parties
      |> List.foldl (.due >> Decimal.fromString >> withDefault zero >> add) zero
    actualtotal = if thing.total_due_set then totaldue else setduesum 

    duedefault =
      if thing.total_due_set
      then
        let
          parties_n = List.length thing.parties
          setdue_n = thing.parties
            |> List.filter (.due_set)
            |> List.foldl ((+) << const 1) 0
          unsetdue_n = parties_n - setdue_n
        in
          case Decimal.fastdiv
            (Decimal.sub totaldue setduesum)
            (Decimal.fromInt unsetdue_n)
          of
            Nothing -> ""
            Just v -> fixed2 v
      else "" -- will not be used
  in
    div [ class "card" ]
      [ div [ class "card-header" ]
        [ p [ class "card-header-title name" ]
          [ text <| if isBlank thing.name then thing.id else thing.name
          ]
        , span [ class "actualtotal" ]
          [ text <| (fixed2 actualtotal) ++ " " ++ thing.asset
          ]
        , span [ class "date" ] [ text <| dateShort thing.actual_date]
        ]
      , div [ class "card-content" ]
        [ table []
          [ thead []
            [ tr []
              [ th [] [ text "person" ]
              , th [] [ text "due" ]
              , th [] [ text "paid" ]
              , th [] [ text "confirmed" ]
              ]
            ]
          , tbody []
            <| List.map (viewPartyRow duedefault) thing.parties
          ]
        ]
      , div [ class "card-footer" ] <|
        if thing.txn /= "" then
         [ span [ class "card-footer-item" ] [ text "Published on Stellar" ]
         , a
           [ class "card-footer-item"
           , href <| "https://stellar.debtmoney.xyz/testnet/#/txn/" ++ thing.txn
           , target "_blank"
           ] [ text <| wrap thing.txn ]
         ]
        else if is_confirmed then
          [ a [ class "card-footer-item", onClick <| ConfirmThing False ] [ text "Unconfirm" ]
          , if thing.publishable
            then a [ class "card-footer-item", onClick PublishThing ] [ text "Publish" ]
            else span [ class "card-footer-item" ] [ text "Confirmed" ]
          ]
        else
          [ a
            [ class "card-footer-item"
            , onClick EditThing
            ] [ text "Edit" ]
          , a [ class "card-footer-item", onClick <| ConfirmThing True ] [ text "Confirm" ]
          ]
      ]

viewPartyRow : String -> Party -> Html ThingMsg
viewPartyRow duedefault party =
  tr []
    [ td []
      [ if party.user_id == ""
        then text party.account_name
        else Html.map ThingGlobalAction <| link ("/user/" ++ party.user_id) party.user_id
      ]
    , td []
      [ text <|
        if party.due_set
        then fixed2 <| withDefault zero <| Decimal.fromString party.due
        else duedefault
      ]
    , td [] [ text <| fixed2 <| withDefault zero <| Decimal.fromString party.paid ]
    , td [] [ text <| if party.confirmed then "yes" else "no" ]
    ]

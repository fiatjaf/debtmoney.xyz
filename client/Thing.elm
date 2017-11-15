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
import Html.Attributes exposing (class, value, colspan, href, target)
import Html.Events exposing (onInput, onClick, on)
import Maybe exposing (withDefault)
import Json.Decode as J
import Array exposing (Array)
import Decimal exposing (Decimal, zero, add, mul, fastdiv, sub, eq)
import GraphQL.Client.Http
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var
import Prelude exposing (..)
import String exposing (trim)
import String.Extra exposing (nonEmpty, isBlank)

import Helpers exposing (..)
import Data.Currencies

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
  , v : Int
  }

defaultParty = Party "" "" "" "" False "" "" "" False 0

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
  |> withLocalConstant defaultParty.v

editingThingMutation : Document Mutation Thing EditingThing
editingThingMutation =
  extract
    ( field "createThing"
      [ ( "date"
        , Arg.variable
          <| Var.optional "date" (.date >> trim >> nonEmpty) Var.string "now"
        )
      , ( "name"
        , Arg.variable
          <| Var.optional "name" (.name >> trim >> nonEmpty) Var.string ""
        )
      , ( "asset", Arg.variable <| Var.required "asset" .asset Var.string )
      , ( "total_due", Arg.variable <| Var.required "total_due" .total Var.string )
      , ( "parties", Arg.variable <| Var.required "parties" (.parties >> Array.toList)
          ( Var.list
            ( Var.object "InputPartyType"
              [ Var.field "account" (.account_name >> trim) Var.string
              , Var.field "paid" .paid Var.string
              , Var.field "due" .due Var.string
              ]
            )
          )
        )
      ]
      thingSpec
    )
    |> mutationDocument

publishThingMutation : Document Mutation Thing String
publishThingMutation =
  extract
    ( field "publishThing"
      [ ( "thing_id", Arg.variable <| Var.required "thing_id" identity Var.string )
      ]
      thingSpec
    )
    |> mutationDocument

confirmThingMutation : Document Mutation Thing String
confirmThingMutation =
  extract
    ( field "confirmThing"
      [ ( "thing_id", Arg.variable <| Var.required "thing_id" identity Var.string )
      ]
      thingSpec
    )
    |> mutationDocument


-- MODEL


type alias EditingThing =
  { date : String 
  , name : String
  , asset : String
  , total : String
  , parties : Array Party
  }

defaultEditingThing = EditingThing "now" "a splitted bill" "" "" Array.empty


-- UPDATE

type ThingMsg
  = ConfirmThing
  | PublishThing
  | GotConfirmationResponse (Result GraphQL.Client.Http.Error Thing)

type EditingThingMsg
  = SetTotal String
  | SetName String
  | SetAsset String
  | AddParty String String String
  | EnsureParty String
  | UpdateParty Int UpdatePartyMsg
  | RemoveParty Int
  | Submit
  | GotSubmitResponse (Result GraphQL.Client.Http.Error Thing)

type UpdatePartyMsg
  = SetPartyAccount String
  | SetPartyDue String
  | SetPartyPaid String

updateEditingThing : EditingThingMsg -> EditingThing -> EditingThing
updateEditingThing change vars =
  case change of
    SetTotal value -> { vars | total = decimalize vars.total value }
    SetName name -> { vars | name = name }
    SetAsset asset -> { vars | asset = asset }
    AddParty account_name due paid ->
      { vars
        | parties = vars.parties
          |> Array.push
            { defaultParty | account_name = account_name, due = due, paid = paid }
      }
    EnsureParty account_name ->
      if (Array.length <| Array.filter (.account_name >> (==) account_name) vars.parties) > 0
      then vars
      else
        { vars
          | parties = vars.parties
            |> Array.push { defaultParty | account_name = account_name }
        }
    UpdateParty index upd ->
      case Array.get index vars.parties of
        Nothing -> case upd of
          SetPartyAccount account_name -> updateEditingThing (AddParty account_name "" "") vars
          SetPartyDue due -> updateEditingThing (AddParty "" (decimalize "" due) "") vars
          SetPartyPaid paid -> updateEditingThing (AddParty "" "" (decimalize "" paid)) vars
        Just prevparty ->
          let party = { prevparty | v = prevparty.v + 1 } -- force view update
          in { vars
            | parties = vars.parties
              |> Array.set index
                ( case upd of
                  SetPartyAccount account_name -> { party | account_name = account_name }
                  SetPartyDue due -> { party | due = decimalize party.due due }
                  SetPartyPaid paid -> { party | paid = decimalize party.paid paid }
                )
          }
    RemoveParty index ->
      let
        before = Array.slice 0 index vars.parties
        after = Array.slice (index + 1) 0 vars.parties
      in { vars | parties = Array.append before after }
    Submit -> vars -- should never happen because we filter for it first.
    GotSubmitResponse _ -> vars -- will never happen


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
      , div [ class "card-footer" ]
        <| if thing.txn == ""
           then
             [ a [ class "card-footer-item" ] [ text "Edit" ]
             , if is_confirmed
               then if thing.publishable
                 then a [ class "card-footer-item", onClick PublishThing ] [ text "Publish" ]
                 else span [ class "card-footer-item" ] [ text "Confirmed" ]
               else a [ class "card-footer-item", onClick ConfirmThing ] [ text "Confirm" ]
             ]
           else
            [ span [ class "card-footer-item" ] [ text "Published on Stellar" ]
            , a
              [ class "card-footer-item"
              , href <| "https://stellar.debtmoney.xyz/testnet/#/txn/" ++ thing.txn
              , target "_blank"
              ] [ text <| wrap thing.txn ]
            ]
      ]

viewPartyRow : String -> Party -> Html msg
viewPartyRow duedefault party =
  tr []
    [ td []
      [ if party.user_id == ""
        then text party.account_name
        else a [] [ text party.user_id ]
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

viewEditingThing : EditingThing -> Html EditingThingMsg
viewEditingThing editingThing =
  let
    sum getter =
      editingThing.parties
        |> Array.map (getter >> Decimal.fromString >> withDefault zero)
        |> Array.foldl add zero
    
    setduesum = editingThing.parties
      |> Array.foldl (.due >> Decimal.fromString >> withDefault zero >> add) zero
    duetotal = Decimal.fromString editingThing.total |> withDefault zero
    actualtotal = if eq duetotal zero then setduesum else duetotal

    parties_n = Array.length editingThing.parties
    setdue_n = editingThing.parties
      |> Array.filter (.due >> (/=) "")
      |> Array.foldl ((+) << const 1) 0
    unsetdue_n = parties_n - setdue_n

    duedefault =
      if duetotal == zero then "" else
        case Decimal.fastdiv
          (Decimal.sub duetotal setduesum)
          (Decimal.fromInt unsetdue_n)
        of
          Nothing -> ""
          Just v -> fixed2 v
  in
    div [ class "editingthing" ]
      [ h1 [ class "title is-4" ] [ text "Declare a new transaction" ]
      , div [ class "asset control" ]
        [ label [] [ text "asset: " ]
        , div [ class "select" ]
          [ select
            [ value editingThing.asset
            , on "change" (J.map SetAsset Html.Events.targetValue )
            ]
            <| List.map
              ( \(code, name) ->
                  option [ value code ]
                    [ text <| if code /= "" then code ++ " (" ++ name ++ ")" else "" ]
              )
            <| (::) ( "", "" )
              Data.Currencies.currencies
          ]
        ]
      , table []
        [ thead []
          [ tr []
            [ th [] [ text "identifier" ]
            , th [] [ text "due" ]
            , th [] [ text "paid" ]
            ]
          , tr []
            [ td [ class "name" ]
              [ input
                [ value editingThing.name
                , onInput SetName
                ] []
              ]
            , td [ class "due-total" ]
              [ input
                [ value <|
                  if eq duetotal zero then fixed2 setduesum
                  else editingThing.total
                , onInput SetTotal
                ] []
              ]
            , td [ class "paid-total" ] [ text <| fixed2 <| sum .paid ]
            ]
          ]
        , tbody []
          <| List.indexedMap (\i -> Html.map (UpdateParty i))
          <| List.indexedMap (lazy3 viewEditingPartyRow duedefault)
          <| flip List.append [ defaultParty ]
          <| Array.toList editingThing.parties
        , tfoot []
          [ tr []
            [ td [ class "summary", colspan 3 ] <|
              if setdue_n == parties_n
                && editingThing.total /= ""
                && (not <| eq
                  (sum .due)
                  (duetotal)
                )
              then
                [ text "mismatched values. the total due is set to "
                , strong []
                  [ text <| fixed2 duetotal
                  ]
                , text " while the sum of all dues is "
                , strong []
                  [ text <| fixed2 <| sum .due
                  ]
                ]
              else if eq actualtotal zero then
                [ text <| "write how much each person was due to pay and "
                       ++ "how much each actually paid."
                ]
              else case Decimal.compare
                  ( sum .paid )
                  ( actualtotal ) of
                EQ ->
                  [ text "everything ok."
                  ]
                LT ->
                  [ strong []
                    [ text <|
                      fixed2
                      <| Decimal.sub
                        ( actualtotal )
                        ( sum .paid )
                    ]
                  , text " left to pay."
                  ]
                GT ->
                  [ strong []
                    [ text <|
                      fixed2
                      <| Decimal.sub
                        ( sum .paid )
                        ( actualtotal )
                    ]
                  , text " overpaid."
                  ]
            ]
          ]
        ]
      , div [ class "button-footer" ]
        [ button
          [ class "button is-primary"
          , onClick Submit
          ] [ text "Save" ]
        ]
      ]

viewEditingPartyRow : String -> Int -> Party -> Html UpdatePartyMsg
viewEditingPartyRow duedefault index party =
  tr []
    [ td [ class "account_name" ]
      [ input
        [ onInput SetPartyAccount
        , value party.account_name
        ] []
      ]
    , td [ class "due" ]
      [ input
        [ onInput SetPartyDue
        , value <|
          if party == defaultParty then ""
          else if party.due == "" then duedefault
          else party.due
        ] []
      ]
    , td [ class "paid" ]
      [ input
        [ onInput SetPartyPaid
        , value party.paid
        ] []
      ]
    ]

module Thing exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a, strong
  , table, tbody, thead, tr, th, td, tfoot
  , input, select, option, header, nav
  , span, section, nav, img, label
  )
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2, lazy3)
import Html.Attributes exposing (class, value, colspan)
import Html.Events exposing (onInput, onClick, on)
import Maybe exposing (withDefault)
import Json.Decode as J
import Array exposing (Array)
import Decimal exposing (Decimal, zero, add, mul, fastdiv, sub, eq)
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var
import Prelude exposing (..)
import String exposing (trim)
import String.Extra exposing (nonEmpty)

import Helpers exposing (..)
import Data.Currencies

type alias Thing =
  { id : String
  , created_at : String
  , actual_date : String
  , created_by : String
  , name : String
  , txn : String
  , parties : List Party
  }

defaultThing = Thing "" "" "" "" "" "" []

type alias Party =
  { thing_id : String
  , user_id : Maybe String
  , account_name : String
  , due : String
  , paid : String
  , note : String
  , added_by : String
  , confirmed : Bool
  , v : Int
  }

defaultParty = Party "" Nothing "" "" "" "" "" False 0

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
  |> with ( field "txn" [] (map (withDefault "") (nullable string)) )
  |> with ( field "parties" [] (list partySpec) )

partySpec = object Party
  |> with ( field "thing_id" [] string )
  |> with ( field "user_id" [] (nullable string) )
  |> with ( field "account_name" [] string )
  |> with ( field "due" [] string )
  |> with ( field "paid" [] string )
  |> with ( field "note" [] string )
  |> with ( field "added_by" [] string )
  |> with ( field "confirmed" [] bool )
  |> withLocalConstant defaultParty.v

newThingMutation : Document Mutation Thing NewThing
newThingMutation =
  let 
    toValidNumber : String -> String
    toValidNumber = Decimal.fromString >> withDefault zero >> fixed2
  in extract
    ( field "createThing"
      [ ( "date"
        , Arg.variable
          <| Var.optional "date" (.date >> trim >> nonEmpty) Var.string "now"
        )
      , ( "name"
        , Arg.variable
          <| Var.optional "name" (.name >> trim >> nonEmpty) Var.string "~"
        )
      , ( "asset", Arg.variable <| Var.required "asset" .asset Var.string )
      , ( "parties", Arg.variable <| Var.required "parties" (.parties >> Array.toList)
          ( Var.list
            ( Var.object "InputPartyType"
              [ Var.field "account" (.account_name >> trim) Var.string
              , Var.field "paid" (.paid >> toValidNumber) Var.string
              , Var.field "due" (.due >> toValidNumber) Var.string
              ]
            )
          )
        )
      ]
      thingSpec
    )
    |> mutationDocument


-- MODEL


type alias NewThing =
  { date : String 
  , name : String
  , asset : String
  , total : String
  , parties : Array Party
  }

defaultNewThing = NewThing "now" "a splitted bill" "" "" Array.empty


-- UPDATE


type NewThingMsg
  = SetTotal String
  | SetName String
  | SetAsset String
  | AddParty String String String
  | EnsureParty String
  | UpdateParty Int UpdatePartyMsg
  | RemoveParty Int
  | Submit

type UpdatePartyMsg
  = SetPartyAccount String
  | SetPartyDue String
  | SetPartyPaid String

updateNewThing : NewThingMsg -> NewThing -> NewThing
updateNewThing change vars =
  case change of
    Submit -> vars -- should never happen because we filter for it first.
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
          SetPartyAccount account_name -> updateNewThing (AddParty account_name "" "") vars
          SetPartyDue due -> updateNewThing (AddParty "" (decimalize "" due) "") vars
          SetPartyPaid paid -> updateNewThing (AddParty "" "" (decimalize "" paid)) vars
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


-- VIEW


thingView : Thing -> Html msg
thingView thing =
  div [ class "thing" ]
    [ h1 [ class "title is-4" ] [ text thing.id ]
    , div [ class "date" ] [ text <| date thing.actual_date ]
    , div [ class "name" ] [ text thing.name ]
    , div [ class "txn" ] [ text thing.txn ]
    ]


viewNewThing : NewThing -> Html NewThingMsg
viewNewThing newThing =
  let
    sum getter =
      newThing.parties
        |> Array.map (getter >> Decimal.fromString >> withDefault zero)
        |> Array.foldl Decimal.add zero
    
    setduesum = newThing.parties
      |> Array.filter (.due >> (/=) "")
      |> Array.foldl
        ( .due
        >> Decimal.fromString
        >> withDefault zero
        >> Decimal.add
        )
        zero
    duetotal = Decimal.fromString newThing.total |> withDefault zero
    actualtotal = if eq duetotal zero then setduesum else duetotal

    parties_n = Array.length newThing.parties
    setdue_n = newThing.parties
      |> Array.filter (.due >> (/=) "")
      |> Array.foldl ((+) << const 1) 0
    unsetdue_n = parties_n - setdue_n

    unsetduedefault =
      if duetotal == zero then "" else
        case Decimal.fastdiv
          (Decimal.sub duetotal setduesum)
          (Decimal.fromInt unsetdue_n)
        of
          Nothing -> ""
          Just v -> fixed2 v

  in
    div [ class "newthing" ]
      [ h1 [ class "title is-4" ] [ text "Declare a new transaction" ]
      , div [ class "asset control" ]
        [ label [] [ text "asset: " ]
        , div [ class "select" ]
          [ select
            [ value newThing.asset
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
                [ value newThing.name
                , onInput SetName
                ] []
              ]
            , td [ class "due-total" ]
              [ input
                [ value <|
                  if eq duetotal zero then fixed2 setduesum
                  else newThing.total
                , onInput SetTotal
                ] []
              ]
            , td [ class "paid-total" ] [ text <| fixed2 <| sum .paid ]
            ]
          ]
        , tbody []
          <| List.indexedMap (\i -> Html.map (UpdateParty i))
          <| List.indexedMap (lazy3 viewNewThingPartyRow unsetduedefault)
          <| flip List.append [ defaultParty ]
          <| Array.toList newThing.parties
        , tfoot []
          [ tr []
            [ td [ class "summary", colspan 3 ] <|
              if setdue_n == parties_n
                && newThing.total /= ""
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

viewNewThingPartyRow : String -> Int -> Party -> Html UpdatePartyMsg
viewNewThingPartyRow duedefault index party =
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

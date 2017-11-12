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
import Html.Events exposing (onInput)
import Array exposing (Array)
import Decimal exposing (Decimal, zero, add, mul, fastdiv, sub, eq)
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var
import Prelude exposing (..)

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
  , due : String
  , paid : String
  , confirmed : Bool
  , registered : Bool
  , v : Int
  }

defaultParty = Party "" "" "" "" False False 0

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
  |> with ( field "due" [] string )
  |> with ( field "paid" [] string )
  |> with ( field "confirmed" [] bool )
  |> with ( field "registered" [] bool )
  |> withLocalConstant defaultParty.v

newThing : Document Mutation ServerResult NewThing
newThing =
  extract
    ( field "newThing"
      [ ( "thing_date", Arg.variable <| Var.required "thing_date" .thing_date Var.string )
      , ( "name", Arg.variable <| Var.required "name" .name Var.string )
      , ( "asset", Arg.variable <| Var.required "asset" .asset Var.string )
      , ( "parties", Arg.variable <| Var.required "parties" (.parties >> Array.toList)
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


-- MODEL


type alias NewThing =
  { thing_date : String 
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

type UpdatePartyMsg
  = SetPartyUser String
  | SetPartyDue String
  | SetPartyPaid String

updateNewThing : NewThingMsg -> NewThing -> NewThing
updateNewThing change vars =
  case change of
    SetTotal value -> { vars | total = decimalize vars.total value }
    SetName name -> { vars | name = name }
    SetAsset asset -> { vars | asset = asset }
    AddParty user_id due paid ->
      { vars
        | parties = vars.parties
          |> Array.push
            { defaultParty | user_id = user_id, due = due, paid = paid }
      }
    EnsureParty user_id ->
      if (Array.length <| Array.filter (.user_id >> (==) user_id) vars.parties) > 0
      then vars
      else
        { vars
          | parties = vars.parties
            |> Array.push { defaultParty | user_id = user_id }
        }
    UpdateParty index upd ->
      case Array.get index vars.parties of
        Nothing -> case upd of
          SetPartyUser user_id -> updateNewThing (AddParty user_id "" "") vars
          SetPartyDue due -> updateNewThing (AddParty "" (decimalize "" due) "") vars
          SetPartyPaid paid -> updateNewThing (AddParty "" "" (decimalize "" paid)) vars
        Just prevparty ->
          let party = { prevparty | v = prevparty.v + 1 } -- force view update
          in { vars
            | parties = vars.parties
              |> Array.set index
                ( case upd of
                  SetPartyUser user_id -> { party | user_id = user_id }
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
    , div [ class "date" ] [ text <| date thing.thing_date ]
    , div [ class "name" ] [ text thing.name ]
    , div [ class "txn" ] [ text thing.txn ]
    ]


viewNewThing : NewThing -> Html NewThingMsg
viewNewThing newThing =
  let
    sum getter =
      newThing.parties
        |> Array.map (getter >> Decimal.fromString >> Maybe.withDefault zero)
        |> Array.foldl Decimal.add zero
    
    setduesum = newThing.parties
      |> Array.filter (.due >> (/=) "")
      |> Array.foldl
        ( .due
        >> Decimal.fromString
        >> Maybe.withDefault zero
        >> Decimal.add
        )
        zero
    duetotal = Decimal.fromString newThing.total |> Maybe.withDefault zero
    actualtotal = if eq duetotal zero then setduesum else duetotal

    parties_n = Array.length newThing.parties
    setdue_n = newThing.parties
      |> Array.filter (.due >> (/=) "")
      |> Array.foldl ((+) << const 1) 0
    unsetdue_n = parties_n - setdue_n

    unsetduedefault = Debug.log "unsetduedefault" <|
      if duetotal == zero then "" else
        case Decimal.fastdiv
          (Decimal.sub duetotal setduesum)
          (Decimal.fromInt unsetdue_n)
        of
          Nothing -> ""
          Just v -> fixed2 v

  in table [ class "newthing" ]
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

viewNewThingPartyRow : String -> Int -> Party -> Html UpdatePartyMsg
viewNewThingPartyRow duedefault index party =
  tr []
    [ td [ class "user_id" ]
      [ input
        [ onInput SetPartyUser
        , value party.user_id
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

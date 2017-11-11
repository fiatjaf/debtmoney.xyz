module Thing exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a, strong
  , table, tbody, thead, tr, th, td, tfoot
  , input, select, option, header, nav
  , span, section, nav, img, label
  )
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy, lazy2)
import Html.Attributes exposing (class, value, colspan)
import Html.Events exposing (onInput)
import Array exposing (Array)
import Decimal exposing (Decimal)
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

sumTotal : (Party -> String) -> NewThing -> Decimal
sumTotal getter newthing =
  newthing.parties
    |> Array.map (getter >> Decimal.fromString >> Maybe.withDefault Decimal.zero)
    |> Array.foldl Decimal.add Decimal.zero

sumPaid = sumTotal .paid >> fixed2
sumDue = sumTotal .due >> fixed2

totalDue : NewThing -> Decimal
totalDue newthing =
  case (
    Decimal.fromString newthing.total
      |> Maybe.andThen
        (\dec -> if Decimal.eq dec Decimal.zero then Nothing else Just dec)
  ) of
    Nothing -> sumTotal .due newthing
    Just dec -> sumTotal .due newthing
  

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
    SetTotal value -> { vars | total = value }
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
  table [ class "newthing" ]
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
            [ value <| sumDue newThing
            , onInput SetTotal
            ] []
          ]
        , td [ class "paid-total" ] [ text <| sumPaid newThing ]
        ]
      ]
    , tbody []
      <| List.indexedMap (\i -> Html.map (UpdateParty i))
      <| List.indexedMap (lazy2 newThingPartyRow)
      <| flip List.append [ defaultParty ]
      <| Array.toList newThing.parties
    , tfoot []
      [ tr []
        [ td [ class "summary", colspan 3 ] <|
          case Decimal.compare
              ( sumTotal .paid newThing )
              ( totalDue newThing ) of
            EQ ->
              [ strong [] [ text "." ]
              , text "ok."
              ]
            LT ->
              [ strong [] [ text ". " ]
              , text
                <| fixed2
                <| Decimal.sub
                  ( totalDue newThing )
                  ( sumTotal .paid newThing )
              , text "left to pay."
              ]
            GT ->
              [ strong [] [ text ". " ]
              , text
                <| fixed2
                <| Decimal.sub
                  ( sumTotal .paid newThing )
                  ( totalDue newThing )
              , text "over."
              ]
        ]
      ]
    ]

newThingPartyRow : Int -> Party -> Html UpdatePartyMsg
newThingPartyRow index party =
  tr []
    [ td [ class "user_id" ]
      [ input
        [ onInput <| SetPartyUser
        , value party.user_id
        ] []
      ]
    , td [ class "due" ]
      [ input
        [ onInput <| SetPartyDue
        , value party.due
        ] []
      ]
    , td [ class "paid" ]
      [ input
        [ onInput <| SetPartyPaid
        , value party.paid
        ] []
      ]
    ]

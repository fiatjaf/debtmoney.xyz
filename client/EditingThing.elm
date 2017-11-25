module EditingThing exposing (..)

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
import Html.Attributes exposing
  ( class, value, colspan, href, target
  , classList, disabled
  )
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
import Select

import Helpers exposing (..)
import Thing exposing (..)
import Data.Currencies


type alias EditingThing =
  { id : String
  , date : String 
  , name : String
  , asset : String
  , total : String
  , parties : Array InputParty
  }

defaultEditingThing =
  EditingThing "" "now" "a splitted bill" "" "" Array.empty

type alias InputParty =
  { user : String
  , due : String
  , paid : String
  , v : Int
  , selectState : Select.State
  , blocked : Bool
  }

defaultInputParty = InputParty "" "" "" 0 (Select.newState "") False

setThingMutation : Document Mutation ServerResult EditingThing
setThingMutation =
  extract
    ( field "setThing"
      [ ( "id" , Arg.variable <| Var.required "id" .id Var.string )
      , ( "date"
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
              [ Var.field "account" (.user >> trim) Var.string
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


type EditingThingMsg
  = SetTotal String
  | SetName String
  | SetAsset String
  | AddParty String String String
  | EnsureParty String
  | UpdateParty Int UpdatePartyMsg
  | RemoveParty Int
  | Submit
  | Delete

updateEditingThing : EditingThingMsg -> EditingThing -> EditingThing
updateEditingThing msg vars =
  case msg of
    SetTotal value -> { vars | total = decimalize vars.total value }
    SetName name -> { vars | name = name }
    SetAsset asset -> { vars | asset = asset }
    AddParty user due paid ->
      { vars
        | parties = vars.parties
          |> Array.push
            { defaultInputParty
              | user = user
              , due = due
              , paid = paid
              , selectState = Select.newState (toString <| Array.length vars.parties)
            }
      }
    EnsureParty user ->
      if (Array.length
          <| Array.filter (.user >> (==) user) vars.parties) > 0
      then vars
      else
        { vars
          | parties = vars.parties
            |> Array.push { defaultInputParty | user = user, blocked = True }
        }
    UpdateParty index upd ->
      case Array.get index vars.parties of
        Nothing -> case upd of
          SetPartyAccount user -> updateEditingThing (AddParty user "" "") vars
          SetPartyDue due -> updateEditingThing (AddParty "" (decimalize "" due) "") vars
          SetPartyPaid paid -> updateEditingThing (AddParty "" "" (decimalize "" paid)) vars
          _ -> vars
        Just prevparty ->
          let
            party = { prevparty | v = prevparty.v + 1 }
          in
            case upd of
              _ ->
                { vars
                  | parties = vars.parties
                    |> Array.set index ( updateInputParty upd party )
                }
    RemoveParty index ->
      let
        before = Array.slice 0 index vars.parties
        after = Array.slice (index + 1) 0 vars.parties
      in { vars | parties = Array.append before after }
    _ -> vars -- should never happen because we filter for it first.


type UpdatePartyMsg
  = SetPartyAccount String
  | SetPartyDue String
  | SetPartyPaid String
  | OnSelect (Maybe String)
  | SelectMsg (Select.Msg String)

updateInputParty : UpdatePartyMsg -> InputParty -> InputParty
updateInputParty msg party =
  case msg of
    SetPartyAccount user -> { party | user = user }
    SetPartyDue due -> { party | due = decimalize party.due due }
    SetPartyPaid paid -> { party | paid = decimalize party.paid paid }
    OnSelect selected ->
      { party | user =
        case  selected of
          Just u -> u
          Nothing -> party.user
      }
    SelectMsg m ->
      let ( s, _ ) = Select.update selectConfig m party.selectState
      in { party | selectState = s }


viewEditingThing : List String -> EditingThing -> Html EditingThingMsg
viewEditingThing friends editingThing =
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
      [ h1 [ class "title is-4" ]
        [ text <| if editingThing.id /= ""
            then "Editing transaction " ++ editingThing.id
            else "Declare a new transaction:"
        ]
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
            , td [ class "paid-total" ]
                [ input [ disabled True, value <| fixed2 <| sum .paid ] []
                ]
            ]
          ]
        , tbody [] <|
          ( editingThing.parties
            |> Array.toList
            |> flip List.append [ defaultInputParty ]
            |> List.indexedMap (lazy3 viewEditingPartyRow (duedefault, friends))
            |> List.indexedMap (\i -> Html.map (UpdateParty i))
          )
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
        [ if editingThing.id /= ""
          then button
            [ class "button is-warning"
            , onClick Delete
            ] [ text "Delete" ]
          else text ""
        , button
          [ class "button is-info"
          , onClick Submit
          ] [ text "Save" ]
        ]
      ]

selectConfig : Select.Config UpdatePartyMsg String
selectConfig =
  Select.newConfig OnSelect identity
    |> Select.withCutoff 5
    |> Select.withInputStyles [ ( "padding", "0.5rem" ), ( "outline", "none" ) ]
    |> Select.withItemClass "border-bottom border-silver p1 gray"
    |> Select.withItemStyles [ ( "font-size", "1rem" ) ]
    |> Select.withMenuClass "border border-gray"
    |> Select.withMenuStyles [ ( "background", "white" ) ]
    |> Select.withNotFoundShown False
    |> Select.withHighlightedItemClass "bg-silver"
    |> Select.withHighlightedItemStyles [ ( "color", "black" ) ]
    |> Select.withPrompt ""
    |> Select.withPromptClass "grey"
    |> Select.withOnQuery SetPartyAccount

viewEditingPartyRow : (String, List String) -> Int -> InputParty -> Html UpdatePartyMsg
viewEditingPartyRow (duedefault, friends) index party =
  tr []
    [ td [ class "user" ]
      [ if party.blocked
        then input [ disabled True, value party.user ] []
        else
          Html.map SelectMsg
            ( Select.view
                selectConfig
                party.selectState
                friends
                ( if isBlank party.user then Nothing else Just party.user )
            )
      ]
    , td [ class "due" ]
      [ input
        [ onInput SetPartyDue
        , value <|
          if party == defaultInputParty then ""
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

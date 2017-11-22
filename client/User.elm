module User exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option, header, nav
  , ul, li, br
  , span, section, nav, img, label, small
  )
import Html.Lazy exposing (lazy, lazy2, lazy3)
import Html.Attributes exposing (class, href, target, title)
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var
import Decimal exposing (Decimal, zero, eq)
import Maybe exposing (withDefault)

import Helpers exposing (..)
import Thing exposing (..)
import EditingThing exposing (..)
import Page exposing (link, GlobalMsg(..))


type alias User =
  { id : String
  , address : String
  , default_asset : String
  , balances : List Balance
  , things : List Thing
  , friends : List String
  , paths : List Path
  }

type alias Path =
  { src_amount : String
  , dst_amount : String
  , path : List Asset
  }

type alias Balance =
  { asset : Asset
  , amount : String
  , limit : String
  }

type alias Asset =
  { code : String
  , issuer_address : String
  , issuer_id : String
  }

defaultUser : User
defaultUser = User "" "" "" [] [] [] []

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
  |> with ( field "default_asset" [] string )
  |> with ( field "balances" [] (list balanceSpec) )
  |> with ( field "things" [] (list thingSpec) )
  |> with ( field "friends" [] (list string) )
  |> with ( field "paths" [] (list pathSpec) )

pathSpec = object Path
  |> with ( field "src_amount" [] string )
  |> with ( field "dst_amount" [] string )
  |> with ( field "path" [] (list assetSpec) )

balanceSpec = object Balance
  |> with ( field "asset" [] assetSpec )
  |> with ( field "amount" [] string )
  |> with ( field "limit" [] string )

assetSpec = object Asset
  |> with ( field "code" [] string )
  |> with ( field "issuer_address" [] string )
  |> with ( field "issuer_id" [] string )


-- UPDATE

type UserMsg
  = UserThingAction Thing ThingMsg
  | UserGlobalAction GlobalMsg
  | UserEditingThingAction EditingThingMsg


-- VIEW


viewUser : User -> User -> Html UserMsg
viewUser me user =
  let
    sumrel : User -> User -> String
    sumrel issuer holder =
      let
        pairs = holder.balances
          |> List.filter (.asset >> .issuer_address >> (==) issuer.address)
          |> List.filter
            (.amount >> Decimal.fromString >> withDefault zero >> eq zero >> not)
          |> List.map (\x -> (pretty2 x.amount) ++ " " ++ x.asset.code)
      in case List.reverse pairs of
        [] -> "nothing"
        [pair] -> pair
        last::pairs -> (String.join ", " pairs) ++ " and " ++ last

    credit = sumrel user me
    debit = sumrel me user 

    path : Html UserMsg
    path = user.paths
      |> List.map (.path >> List.map viewAsset >> List.intersperse (text " → ") >> li [])
      |> ul []
      |> Html.map UserGlobalAction
  in
    div [ class "user" ]
      [ h1 [ class "title is-1" ]
        [ text <| user.id ++ "'s" ++ " profile"
        ]
      , div [ class "section relationship" ]
        [ h2 [ class "title is-4" ] [ text "credit relationship:" ]
        , p [] [ text <| "You owe " ++ debit ++ " to " ++ user.id ++ "." ]
        , p [] [ text <| user.id ++ " owes you " ++ credit ++ "." ]
        , br [] []
        , if List.length user.paths == 0
          then text ""
          else div []
            [ text <| "You can make a payment to " ++ user.id ++ " using your current assets:"
            , path
            ]
        ]
      , div [ class "section things" ]
        [ h2 [ class "title is-4" ]
          [ text <| "transactions involving you and " ++ user.id ++ ":"
          ]
        , div []
            <| List.map
              (\t -> Html.map (UserThingAction t)
                <| lazy3 viewThingCard me.id user.id t
              )
            <| user.things
        ]
      , div [ class "section address" ]
        [ h2 [ class "title is-4" ] [ text "address:" ]
        , p [] [ text user.address]
        ]
      , div [ class "section" ]
        [ h2 [ class "title is-4" ] [ text "balances:" ]
        , table [ class "table is-striped is-fullwidth" ]
          [ thead []
            [ tr []
              [ th [] [ text "asset" ]
              , th [] [ text "amount" ]
              , th [] [ text "trust limit" ]
              ]
            ]
          , tbody []
            <| List.map (Html.map UserGlobalAction << balanceRow) user.balances
          ]
        ]
      ]

balanceRow : Balance -> Html GlobalMsg
balanceRow balance =
  tr []
    [ td [] [ viewAsset balance.asset ]
    , td [] [ text balance.amount ]
    , td [] [ text balance.limit ]
    ]

viewAsset : Asset -> Html GlobalMsg
viewAsset asset =
  span [ class "asset" ]
    [ text asset.code
    , small []
      [ text "[ "
      , if asset.issuer_id /= ""
        then link ("/user/" ++ asset.issuer_id) (asset.issuer_id)
        else a
          [ href <| "https://stellar.debtmoney.xyz/#/addr/" ++ asset.issuer_address
          , target "_blank"
          , title asset.issuer_address
          ] [ text <| wrap asset.issuer_address ]
      , text " ]"
      ]
    ]

viewHome : User -> EditingThing -> Html UserMsg
viewHome user editingThing =
  div []
    [ Html.map UserEditingThingAction
      ( lazy2 viewEditingThing user.friends editingThing )
    , div [ class "section" ]
      [ h2 [ class "title is-4" ] [ text "transactions:" ]
      , div [ class "things" ]
          <| List.map
            (\t -> Html.map (UserThingAction t)
              <| lazy3 viewThingCard user.id user.id t
            )
          <| user.things
      ]
    , div [ class "section" ]
      [ h2 [ class "title is-4" ] [ text "address:" ]
      , p [] [ text user.address]
      ]
    , div [ class "section" ]
      [ h2 [ class "title is-4" ] [ text "balances:" ]
      , table [ class "table is-striped is-fullwidth" ]
        [ thead []
          [ tr []
            [ th [] [ text "asset" ]
            , th [] [ text "amount" ]
            , th [] [ text "trust limit" ]
            ]
          ]
        , tbody []
          <| List.map (Html.map UserGlobalAction << balanceRow) user.balances
        ]
      ]
    ]

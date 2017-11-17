module User exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option, header, nav
  , span, section, nav, img, label
  )
import Html.Lazy exposing (lazy, lazy2, lazy3)
import Html.Attributes exposing (class, href, target, title)
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var

import Helpers exposing (..)
import Thing exposing (..)
import Page exposing (link, GlobalMsg(..))


type alias User =
  { id : String
  , address : String
  , default_asset : String
  , balances : List Balance
  , things : List Thing
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
defaultUser = User "" "" "" [] []

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
  div [ class "user" ]
    [ h1 []
      [ text <| user.id ++ "'s" ++ " profile"
      ]
    , div [ class "section" ]
      [ h2 [ class "title is-4" ] [ text "transactions:" ]
      , div [ class "things" ]
          <| List.map
            (\t -> Html.map (UserThingAction t)
              <| lazy3 viewThingCard me.id user.id t
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
    , text "#"
    , if asset.issuer_id /= ""
      then link ("/user/" ++ asset.issuer_id) (asset.issuer_id)
      else a
        [ href <| "https://stellar.debtmoney.xyz/#/addr/" ++ asset.issuer_address
        , target "_blank"
        , title asset.issuer_address
        ] [ text <| wrap asset.issuer_address ]
    ]

viewHome : User -> EditingThing -> Html UserMsg
viewHome user editingThing =
  div []
    [ Html.map UserEditingThingAction
      ( lazy viewEditingThing editingThing )
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

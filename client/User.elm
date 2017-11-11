module User exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option, header, nav
  , span, section, nav, img, label
  )
import Html.Attributes exposing (class)
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


-- VIEW


userView : User -> Html msg
userView user =
  div [ class "user" ]
    [ h1 []
      [ text <| user.id ++ "'s" ++ " profile"
      ]
    , div []
      [ h2 [] [ text "operations:" ]
      , table [ class "table is-hoverable is-fullwidth" ]
        [ thead []
          [ tr []
            [ th [] [ text "date" ]
            , th [] [ text "description" ]
            , th [] [ text "confirmed" ]
            ]
          ]
        , tbody [] []
          -- <| List.map (thingRow user.id) user.things
        ]
      ]
    , div []
      [ h2 [] [ text "address:" ]
      , p [] [ text user.address]
      ]
    , div []
      [ h2 [] [ text "balances:" ]
      , table [ class "table is-striped is-fullwidth" ]
        [ thead []
          [ tr []
            [ th [] [ text "asset" ]
            , th [] [ text "amount" ]
            , th [] [ text "trust limit" ]
            ]
          ]
        , tbody []
          <| List.map assetRow user.balances
        ]
      ]
    ]


assetRow : Balance -> Html msg
assetRow balance =
  tr []
    [ td [] [ text balance.asset ]
    , td [] [ text balance.amount ]
    , td [] [ text balance.limit ]
    ]

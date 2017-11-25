module User exposing (..)

import Html exposing
  ( Html, text
  , h1, h2, div, textarea, button, p, a
  , table, tbody, thead, tr, th, td
  , input, select, option, header, nav
  , ul, li, br, form
  , span, section, nav, img, label, small
  )
import Html.Lazy exposing (lazy2, lazy3)
import Html.Events exposing (onWithOptions)
import Html.Attributes exposing
  ( class, href, target, title, name, colspan
  , max, type_, value, step
  )
import GraphQL.Request.Builder exposing (..)
import GraphQL.Request.Builder.Arg as Arg
import GraphQL.Request.Builder.Variable as Var
import Json.Decode as J
import Decimal exposing (Decimal, zero, eq)
import Tuple exposing (..)
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
  { src : Asset
  , dst : Asset
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
  |> with ( field "src" [] assetSpec )
  |> with ( field "dst" [] assetSpec )
  |> with ( field "path" [] (list assetSpec) )

balanceSpec = object Balance
  |> with ( field "asset" [] assetSpec )
  |> with ( field "amount" [] string )
  |> with ( field "limit" [] string )

assetSpec = object Asset
  |> with ( field "code" [] string )
  |> with ( field "issuer_address" [] string )
  |> with ( field "issuer_id" [] string )

type alias SendPaymentVars =
  { dst_user : String
  , dst_address : String
  , dst_code : String
  , src_address : String
  , src_code : String
  , amount : String
  }

sendPaymentMutation : Document Mutation ServerResult SendPaymentVars
sendPaymentMutation =
  extract
    ( field "sendPayment"
      [ ( "dst_user" , Arg.variable <| Var.required "dst_user" .dst_user Var.string )
      , ( "dst_code" , Arg.variable <| Var.required "dst_code" .dst_code Var.string )
      , ( "dst_address" , Arg.variable <| Var.required "dst_address" .dst_address Var.string )
      , ( "src_code" , Arg.variable <| Var.required "src_code" .src_code Var.string )
      , ( "src_address" , Arg.variable <| Var.required "src_address" .src_address Var.string )
      , ( "amount" , Arg.variable <| Var.required "amount" .amount Var.string )
      ]
      serverResultSpec
    )
    |> mutationDocument

-- UPDATE

type UserMsg
  = SendPayment SendPaymentVars
  | UserThingAction Thing ThingMsg
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

    intoList
      : Path
      -> List ((Asset, Asset), List (List Asset))
      -> List ((Asset, Asset), List (List Asset))
    intoList path acc =
      let
        compare ((src, dst), _) = src == path.src && dst == path.dst
      in
        if acc |> List.filter compare |> List.isEmpty
        then ((path.src, path.dst), [ path.path ]) :: acc
        else
          acc
            |> List.map
              ( \(key, paths) ->
                if compare (key, paths)
                then (key, path.path :: paths)
                else (key, paths)
              )

    pathsByAssets : List ((Asset, Asset), List (List Asset))
    pathsByAssets = user.paths
      |> List.filter (.path >> List.filter (.issuer_id >> (==) me.id) >> List.isEmpty)
      |> List.foldl intoList []

    totalBalance : Asset -> String
    totalBalance asset = me.balances
      |> List.filter
        (\b -> b.asset.code == asset.code && b.asset.issuer_address == asset.issuer_address)
      |> List.head
      |> Maybe.map .amount
      |> Maybe.withDefault "0.00"
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
            [ text <|
              "You can make a payment to " ++ user.id ++ " using your current IOU balances:"
            , table [ class "payment" ]
              [ thead []
                [ th [] [ text "you send" ]
                , th [ colspan 3 ] [ text "the assets go through a path" ]
                , th [] [ text <| user.id ++ " receives" ]
                , th [] []
                ]
              , tbody []
                  <| List.map (\((s, d), p) -> pathListRow (totalBalance s) ((s, d), p))
                  <| pathsByAssets
              ]
            ]
        ]
      , div [ class "section" ]
        [ h2 [ class "title is-4" ]
          [ text <| "transactions involving you and " ++ user.id ++ ":"
          ]
        , div [ class "things" ]
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

pathListRow : String -> ((Asset, Asset), List (List Asset)) -> Html UserMsg
pathListRow total ((src, dst), paths) =
  tr []
    [ Html.map UserGlobalAction <| td [ class "path-src" ] [ viewAsset src ]
    , td [ class "arrow" ] [ text " → " ]
    , Html.map UserGlobalAction <| td []
      [ div [ class "path-list" ] <|
        List.map
          ( ( (List.map viewAsset)
            >> List.intersperse (text " → ")
            >> List.map (List.singleton >> li [])
            )
          >> (\items -> if List.isEmpty items then text "(direct)" else ul [] items)
          )
          paths
      ]
    , td [ class "arrow" ] [ text " → " ]
    , Html.map UserGlobalAction <| td [ class "path-dst" ] [ viewAsset dst ]
    , td []
      [ form 
        [ onWithOptions
          "submit"
          {stopPropagation=False, preventDefault=True}
          ( J.map SendPayment ( J.map6 SendPaymentVars
            ( J.succeed "" )
            ( J.succeed dst.issuer_address )
            ( J.succeed dst.code )
            ( J.succeed src.issuer_address )
            ( J.succeed src.code )
            ( J.at [ "target", "payment", "value" ] J.string )
          ))
        ]
        [ input
          [ class "input is-small"
          , name "payment"
          , value total
          , Html.Attributes.max total
          , step "0.01"
          ] []
        , button [ class "button is-small" ] [ text "Pay" ]
        ]
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

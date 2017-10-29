module Record exposing
  ( Record, Desc(..), recordDecoder
  , defaultRecord
  , DeclareDebt, setCreditor, setAsset, setAmount, declareDebtEncoder
  )

import Dict exposing (Dict)
import Json.Decode as J exposing (field, list, int, string, bool)
import Json.Encode as E


type alias Record =
  { id : Int
  , date : String
  , kind : String
  , asset : String
  , desc : Desc
  , confirmed : List String
  , transactions : List String
  }


defaultRecord : Record
defaultRecord = Record 0 "" "" "" Blank [] []


type Desc
  = Debt DebtDescription
  | Payment PaymentDescription
  | BillSplit BillSplitDescription
  | Blank

type alias DebtDescription =
  { debtor : String
  , creditor : String
  , amount : String
  }
type alias PaymentDescription =
  { payer : String
  , payee : String
  , amount : String
  , object : String
  }
type alias BillSplitDescription =
  { parties : Dict String { due : String, paid : String }
  , object : String
  }


recordDecoder : J.Decoder Record
recordDecoder =
  J.map7 Record
    ( field "id" int )
    ( field "created_at" string )
    ( field "kind" string )
    ( field "asset" string )
    ( field "description" <| J.oneOf [ debtDecoder, paymentDecoder, billSplitDecoder ] )
    ( field "confirmed" <| list string )
    ( field "transactions" <| list string )

debtDecoder : J.Decoder Desc
debtDecoder =
  J.map Debt <| J.map3 DebtDescription
    ( field "debtor" string )
    ( field "creditor" string )
    ( field "amt" string )

paymentDecoder : J.Decoder Desc
paymentDecoder =
  J.map Payment <| J.map4 PaymentDescription
    ( field "payer" string )
    ( field "payee" string )
    ( field "amt" string )
    ( field "obj" string )

billSplitDecoder : J.Decoder Desc
billSplitDecoder =
  J.map BillSplit <| J.map2 BillSplitDescription
    ( J.dict
      <| J.map2 (\d p -> { due=d, paid=p })
        ( field "due" string )
        ( field "due" string )
    )
    ( field "obj" string )

type alias DeclareDebt =
  { creditor : String
  , asset : String
  , amount : String
  }

setCreditor x dd = { dd | creditor = x } 
setAsset x dd = { dd | asset = x } 
setAmount x dd = { dd | amount = x } 

declareDebtEncoder: DeclareDebt -> E.Value
declareDebtEncoder d =
  E.object
    [ ( "creditor", E.string d.creditor )
    , ( "asset", E.string d.asset )
    , ( "amount", E.string d.amount )
    ]

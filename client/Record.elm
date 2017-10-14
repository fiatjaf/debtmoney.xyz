module Record exposing
  ( Record, Desc(..), recordDecoder
  , defaultRecord
  , DeclareDebt, setCreditor, setAsset, setAmount, declareDebtEncoder
  )

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
  | Blank

type alias DebtDescription = { from : String, to : String, amount : String }


recordDecoder : J.Decoder Record
recordDecoder =
  J.map7 Record
    ( field "id" int )
    ( field "created_at" string )
    ( field "kind" string )
    ( field "asset" string )
    ( field "description" <| J.oneOf [ debtDecoder ] )
    ( field "confirmed" <| list string )
    ( field "transactions" <| list string )

debtDecoder : J.Decoder Desc
debtDecoder =
  J.map3 ( \a b c -> Debt (DebtDescription a b c) )
    ( field "from" string )
    ( field "to" string )
    ( field "amt" string )


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

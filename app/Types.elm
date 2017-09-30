module Types exposing (..)

type alias User =
  { id : String
  , address : String
  , balances : List Balance
  }

type alias Balance =
  { asset : String
  , amount : String
  }

type alias ResultType =
  { ok : Bool
  , value : String
  , error : String
  }

type alias DeclareDebt =
  { creditor : String
  , asset : String
  , amount : String
  }

setCreditor x dd = { dd | creditor = x } 
setAsset x dd = { dd | asset = x } 
setAmount x dd = { dd | amount = x } 

module Types exposing (..)

type alias User =
  { name : String
  , balances : List Balance
  }

type alias Balance =
  { asset : String
  , amount : Int
  }

module User exposing (User, Balance, defaultUser, userDecoder, balanceDecoder)

import Json.Decode as J exposing (field, list, int, string, bool)

import Record


type alias User =
  { id : String
  , address : String
  , balances : List Balance
  , records : List Record.Record
  }

type alias Balance =
  { asset : String
  , amount : String
  }

defaultUser : User
defaultUser = User "" "" [] []


userDecoder : J.Decoder User
userDecoder =
  J.map4 User
    ( field "id" string )
    ( field "address" string )
    ( field "balances" <| list balanceDecoder )
    ( field "balances" <| list Record.recordDecoder )

balanceDecoder : J.Decoder Balance
balanceDecoder =
  J.map2 Balance
    ( field "asset" string )
    ( field "amount" string )

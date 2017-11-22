module Helpers exposing (..)

import Http
import Task
import Process
import Time exposing (Time)
import Platform.Cmd as Cmd
import Date
import Date.Format
import FormatNumber
import FormatNumber.Locales exposing (usLocale)
import Decimal exposing (Decimal)
import GraphQL.Client.Http exposing (Error(..))
import GraphQL.Request.Builder exposing (..)
import Prelude exposing (..)


decimalize : String -> String -> String
decimalize default n =
  if n == "" then "" else String.toFloat n
   |> Result.map (\f -> if f < 0 then default else n)
   |> Result.withDefault default

fixed2 : Decimal -> String
fixed2 = Decimal.toFloat >> FormatNumber.format usLocale

pretty2 : String -> String
pretty2 = Decimal.fromString >> Maybe.map fixed2 >> Maybe.withDefault "0.00"

errorFormat : GraphQL.Client.Http.Error -> String
errorFormat err =
  case err of
    GraphQLError errors ->
      "Errors: " ++ (String.join ". " <| List.map .message errors)
    HttpError httperror ->
      case httperror of
        Http.BadUrl u -> "Bad URL: " ++ u
        Http.Timeout -> "timeout"
        Http.NetworkError -> "NETWORK ERROR"
        Http.BadStatus resp ->
      resp.url ++ " returned " ++ (toString resp.status.code) ++ ": " ++ resp.body
        Http.BadPayload x y -> "Bad payload (" ++ x ++ ")"

type alias ServerResult =
  { value : String
  }

serverResultSpec =
  object ServerResult
    |> with ( field "value" [] (map (Maybe.withDefault "") (nullable string)) )


delay : Time -> msg -> Cmd msg
delay time msg =
  Process.sleep time
    |> Task.andThen (always <| Task.succeed msg)
    |> Task.perform identity

date : String -> String
date
  = Date.fromString
  >> Result.withDefault (Date.fromTime 0)
  >> Date.Format.format "%B %e, %Y, %I:%M:%S %P"

dateShort : String -> String
dateShort
  = Date.fromString
  >> Result.withDefault (Date.fromTime 0)
  >> Date.Format.format "%b %e %Y, %H:%M"

time : String -> String
time
  = Date.fromString
  >> Result.withDefault (Date.fromTime 0)
  >> Date.Format.format "%I:%M:%S %P"

wrap : String -> String
wrap str =
  if str == ""
  then ""
  else (String.left 3 str) ++ "..." ++ (String.right 4 str)
    |> String.toLower

limitwrap : String -> String
limitwrap number = if number == "922337203685.4775807" then "max" else number

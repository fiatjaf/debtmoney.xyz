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


type GlobalAction
  = Navigate

decimalize : String -> String -> String
decimalize default n =
  if n == "" then "" else String.toFloat n
   |> Result.map (\f -> if f < 0 then default else n)
   |> Result.withDefault default

fixed2 : Decimal -> String
fixed2 = Decimal.toFloat >> FormatNumber.format usLocale

errorFormat : GraphQL.Client.Http.Error -> String
errorFormat err =
  case err of
    GraphQLError errors ->
      "errors: " ++ (String.join ". " <| List.map .message errors)
    HttpError httperror ->
      case httperror of
        Http.BadUrl u -> "bad url " ++ u
        Http.Timeout -> "timeout"
        Http.NetworkError -> "network error"
        Http.BadStatus resp ->
      resp.url ++ " returned " ++ (toString resp.status.code) ++ ": " ++ resp.body
        Http.BadPayload x y -> "bad payload (" ++ x ++ ")"

type alias ServerResult =
  { value : String
  }

serverResultSpec = object ServerResult |> with ( field "value" [] string )


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

module Main exposing (..)

import Browser
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)

main =
  Browser.element { init = init, update = update, view = view , subscriptions = subscriptions }

-- MODEL

type alias Model =
  Int

init : () -> (Model, Cmd Msg)
init _ =
  ( 99, Cmd.none )

-- UPDATE

type Msg
  = Increment
  | Decrement
  | Reset

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Increment ->
      (model + 1, Cmd.none)
    Decrement ->
      (model - 1, Cmd.none)
    Reset ->
      (init ())

-- VIEW

view : Model -> Html Msg
view model =
  div []
    [ button [ onClick Decrement ] [ text "-" ]
    , text (String.fromInt model)
    , button [ onClick Increment ] [ text "+" ]
    , div [] [ text "help me pls" ]
    , button [ onClick Reset ] [ text "reset" ]
    ]

-- SUBSCRIPTIONS

subscriptions : model -> Sub msg
subscriptions model =
  Sub.none

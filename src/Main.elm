port module Main exposing (..)

import Browser
import File exposing (File)
import File.Select
import Html exposing (Html, button, div, figcaption, figure, h2, img, input, label, p, text)
import Html.Attributes exposing (class, multiple, src, style, type_)
import Html.Events exposing (on)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy)
import Json.Decode as JD
import Json.Decode.Pipeline as JP


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { images : List Image
    , jobs : List Job
    }



-- making sure its serializable over port


type alias Job =
    { id : ImageID
    , file : JSFile
    , started : Bool
    }


type alias JSFile =
    JD.Value


type alias ImageURL =
    String



-- bloburl or asset path or something


type alias ImageID =
    Int


type alias Image =
    { id : ImageID
    , description : String
    , status : ImageStatus
    }


type ImageStatus
    = Loaded ImageURL
    | NotLoaded


type JobResult
    = Success ImageURL
    | Error String


type alias JobResultWithID =
    { id : ImageID
    , result : JobResult
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { images =
            [ { status = NotLoaded, description = "hasn't been loaded yet", id = 0 }
            ]
      , jobs = []
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = Noop
    | JobFinished JD.Value -- { id : ImageID, successful : Bool, url : ImageURL }
    | FileListChosen JD.Value -- [ File(JS Obj) ]
    | RemovePicture ImageID
    | MakePDF
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Noop ->
            ( model, Cmd.none )

        FileListChosen fileListJson ->
            let
                maxID =
                    model.images
                        |> List.map (\image -> image.id)
                        |> List.foldl Basics.max 0

                filepathDecoder : JD.Decoder String
                filepathDecoder =
                    JD.field "url" JD.string

                imageDecoder : JD.Decoder Image
                imageDecoder =
                    JD.map3 Image
                        (JD.succeed 0)
                        -- id: placeholder, replaced later
                        (JD.succeed "description")
                        -- description: placeholder too
                        -- (JD.map (\filepath -> Loaded filepath) filepathDecoder)
                        (JD.succeed NotLoaded)

                -- status: loaded object url for image file
                fileListDecoder : JD.Decoder (List Image)
                fileListDecoder =
                    JD.list imageDecoder

                newImages =
                    fileListJson
                        |> JD.decodeValue fileListDecoder
                        |> (\result ->
                                case result of
                                    Ok imageList ->
                                        imageList
                                            |> List.indexedMap
                                                (\i image ->
                                                    { id = maxID + i + 1
                                                    , description = String.fromInt (i + maxID)
                                                    , status = image.status
                                                    }
                                                )

                                    Err decodeErr ->
                                        decodeErr
                                            |> Debug.log "Image decoding error"
                                            |> (\_ -> [])
                           )

                ( updatedJobs, cmd ) =
                    let
                        jsfiles =
                            fileListJson
                                |> JD.decodeValue (JD.list JD.value)
                                |> (\result ->
                                        case result of
                                            Ok fileList ->
                                                fileList

                                            Err decodeErr ->
                                                decodeErr
                                                    |> Debug.log "FileList decoding error"
                                                    |> (\_ -> [])
                                   )
                    in
                    newImages
                        |> List.map (\image -> image.id)
                        |> List.map2 (\jsfile id -> { id = id, file = jsfile, started = False }) jsfiles
                        |> List.append model.jobs
                        |> maybeStartJobs
            in
            ( { model | images = model.images ++ newImages, jobs = updatedJobs }, cmd )

        JobFinished jobResultJson ->
            let
                resultDecoder : JD.Decoder JobResult
                resultDecoder =
                    JD.oneOf
                        [ JD.map (\url -> Success url) (JD.field "url" JD.string)
                        , JD.map (\errorMsg -> Error errorMsg) (JD.field "error" JD.string)
                        ]

                idDecoder : JD.Decoder ImageID
                idDecoder =
                    JD.field "id" JD.int

                jobResultDecoder : JD.Decoder JobResultWithID
                jobResultDecoder =
                    JD.map2 JobResultWithID
                        idDecoder
                        resultDecoder

                job =
                    jobResultJson
                        |> JD.decodeValue jobResultDecoder
                        |> (\result ->
                                case result of
                                    Ok jobResult ->
                                        jobResult

                                    Err decodeErr ->
                                        decodeErr
                                            |> Debug.log "Job result decoding error"
                                            |> (\_ -> { id = -1, result = Error "" })
                           )

                ( updatedJobs, cmd ) =
                    case model.jobs of
                        finished :: remaining ->
                            maybeStartJobs remaining

                        [] ->
                            ( [], Cmd.none )

                updatedImages =
                    model.images
                        |> List.map
                            (\image ->
                                if image.id == job.id then
                                    case job.result of
                                        Success url ->
                                            { image | status = Loaded url }

                                        Error errorMsg ->
                                            errorMsg
                                                |> Debug.log "Job failed"
                                                |> (\_ -> image)

                                else
                                    image
                            )
            in
            ( { model
                | jobs = updatedJobs
                , images = updatedImages
              }
            , cmd
            )

        RemovePicture imgID ->
            ( { model
                | images =
                    model.images
                        |> List.filter (\image -> image.id /= imgID)
                , jobs =
                    model.jobs
                        |> List.filter (\job -> job.id /= imgID)
              }
            , Cmd.none
            )

        MakePDF ->
            ( model
            , model.images
                |> List.filter (\image -> image.status /= NotLoaded)
                |> List.map (\image -> stringifyImageID image.id)
                |> portImagesFromElm
            )

        NoOp ->
            ( model, Cmd.none )



-- PORTS


port portJobFromElm : Job -> Cmd msg


port portJobToElm : (JD.Value -> msg) -> Sub msg


port portFilesFromElm : JD.Value -> Cmd msg


port portFilesToElm : (JD.Value -> msg) -> Sub msg


port portImagesFromElm : List String -> Cmd msg



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ portJobToElm JobFinished
        ]



-- UPDATE


maybeStartJobs : List Job -> ( List Job, Cmd Msg )
maybeStartJobs jobs =
    case jobs of
        first :: remaining ->
            if not first.started then
                ( { first | started = True } :: remaining
                , portJobFromElm first
                )

            else
                ( jobs, Cmd.none )

        _ ->
            ( jobs, Cmd.none )


stringifyImageID : ImageID -> String
stringifyImageID imgID =
    -- internal ID to html-safe id, where ids can't start with a number
    "fig" ++ String.fromInt imgID



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ class "gallery-container"
        ]
        [ h2 [] [ text "gallery" ]
        , Keyed.node "div"
            [ class "gallery"
            , onDragOver NoOp
            , onDragDrop (\rawJson -> FileListChosen rawJson)
            ]
            (List.map viewKeyedThumbnail model.images)
        , div
            []
            [ fileUploadBtn
                [ onFilesUploaded (\rawJson -> FileListChosen rawJson) ]
                []
            ]
        , button
            [ onClick (\_ -> MakePDF) ]
            [ text "make pdf" ]
        ]



-- probably need to manually have a hidden <input type=file multiple> so i can have a custom handler that keeps the native JS File obj around, for the sake of blob urls or whatever
-- e.target.files = FileList
-- e.target.files[0] = {lastModified=1690..., lastModifiedDate=Date, name="filename", path="some/path/filenname", size=12345..., type="mime/something"}
--
-- EDIT: elm cant trigger click event on hidden file input :(


onDragOver : Msg -> Html.Attribute Msg
onDragOver msg =
    -- must prevent default ondragover in order to let ondrop event bubble through
    Html.Events.preventDefaultOn "dragover"
        (JD.map
            (\_ -> ( msg, True ))
            (JD.succeed ())
        )


onDragDrop : (JD.Value -> Msg) -> Html.Attribute Msg
onDragDrop produceMsgWith =
    on "drop"
        (JD.map
            (\jsonValue -> produceMsgWith jsonValue)
            (JD.at [ "dataTransfer", "files" ] JD.value)
        )


onFilesUploaded : (JD.Value -> Msg) -> Html.Attribute Msg
onFilesUploaded produceMsgWith =
    -- this is an attribute used like onClick
    -- eg. onFilesUploaded MyMsg, where MyMsg is defined as MyMsg Json.Value
    -- the Json.Value is a FileList in javascript
    --
    -- note how json.map works:
    -- json.map : (a -> val) -> Decoder a -> Decoder val
    --   so the second param is a decoder that returns some type `a`,
    --   the first param is a function that takes `a` and returns something else,
    --   and the return value is a decoder that returns the something else
    on "change"
        (JD.map
            (\jsonValue -> produceMsgWith jsonValue)
            (JD.at [ "target", "files" ] JD.value)
        )


onClick : (() -> Msg) -> Html.Attribute Msg
onClick produceMsg =
    -- trying to make arg a lambda so that it's more intuitive to use
    -- onClick (\_ -> MyMsg with any kind of data)
    -- onFileUpload (\files -> MyMsg files)
    --
    -- as opposed to default onClick
    -- onClick (MyMsg some data too)
    on "click"
        (JD.map
            produceMsg
            (JD.succeed ())
        )


fileUploadBtn : List (Html.Attribute Msg) -> List (Html Msg) -> Html Msg
fileUploadBtn attributes children =
    div [ class "btn" ]
        -- [ button
        --     [ Html.Attributes.attribute "onclick" "javascript:this.nextElementSibling.click()"
        --     ]
        --     [ text "file upload on me" ]
        [ label
            ([ class "btn" ] ++ attributes)
            ([ text "drag and drop or click to upload files"
             , input
                [ type_ "file"
                , multiple True
                , style "display" "none"
                ]
                []
             ]
                ++ children
            )
        ]


noneAttribute : Html.Attribute msg
noneAttribute =
    Html.Attributes.classList []


viewKeyedThumbnail : Image -> ( String, Html Msg )
viewKeyedThumbnail image =
    ( String.fromInt image.id, viewThumbnail image )


viewThumbnail : Image -> Html Msg
viewThumbnail image =
    figure [ Html.Attributes.id (stringifyImageID image.id) ]
        [ img
            [ case image.status of
                Loaded src_ ->
                    src src_

                NotLoaded ->
                    noneAttribute
            ]
            []
        , figcaption
            []
            [ text image.description ]
        , button
            [ class "delete-btn"
            , onClick (\_ -> RemovePicture image.id)
            ]
            [ text "X" ]
        ]

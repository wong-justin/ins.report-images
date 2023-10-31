port module Main exposing (..)

-- import Html.Keyed as Keyed
-- import Html.Lazy exposing (lazy)

import Browser
import Dict exposing (Dict)
import File exposing (File)
import File.Select
import Html exposing (Html, button, div, h2, img, input, p, text)
import Html.Attributes exposing (class, multiple, src, style, type_)
import Html.Events exposing (on, onClick)
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
            [ { status = Loaded "../assets/400x128.jpg", description = "lorem ipsum lorem ipsum", id = 0 }
            , { status = Loaded "../assets/128x128.jpg", description = "lorem ipsum lorem ipsum", id = 1 }
            , { status = Loaded "../assets/128x400.jpg", description = "lorem ipsum lorem ipsum", id = 2 }
            , { status = NotLoaded, description = "hasn't been loaded yet", id = 3 }
            ]
      , jobs = []
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = Noop
      -- | OpenImagePicker
      -- | ImagesUploaded File (List File) -- weird return type from elm people: first file, and other files if they exist (instead of just a list in the first place)
    | JobFinished JD.Value -- { id : ImageID, successful : Bool, url : ImageURL }
    | FileListChosen JD.Value
    | FileListReturned JD.Value
    | RemovePicture ImageID



-- | CancelJob JobID -- remove job from linked list if job is still pending (ie. exists)
-- | DeleteImage ImageID -- remove image with this id from list model.images
-- | ToElmFinishJob CompressResults -- show finished image element, and start next job
-- side effects used in update:
-- * startJob (over a port)
-- * filepicker dialog
-- RequestCompressImages
--| OtherMsgType
--| ReceiveUploadedImages
--| RequestCreateImagePlaceholders --make the whole bunch at one speed
-- each picture will send CompressMsg StartCompress, and on its FinishCompress should tell next picture to start compressing


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Noop ->
            ( model, Cmd.none )

        --  OpenImagePicker ->
        --      ( model, File.Select.files [ "image/*" ] ImagesUploaded )
        -- -- TODO: use ports to get Blob urls from Files, since elm hides the useful aspects of web/js Blob and File objects that i need, aka URL.createObjectURL(blob/file)
        -- ImagesUploaded file remainingFiles ->
        --     let
        --         newImages =
        --             uniteUploads file remainingFiles
        --                 |> List.map imageFromFile
        --         maybeStartJobs : List Job -> ( List Job, Cmd Msg )
        --         maybeStartJobs jobs =
        --             case jobs of
        --                 -- there's at least one existing job and none are started because first isnt started
        --                 -- so update it and start the side effect
        --                 ( jobID, NotStarted ) :: remaining ->
        --                     ( ( jobID, Started ) :: remaining
        --                     , portJobFromElm jobID
        --                     )
        --                 -- else there are already pending jobs, so do nothing
        --                 _ ->
        --                     ( jobs, Cmd.none )
        --         ( updatedJobs, cmd ) =
        --             newImages
        --                 |> List.map (\image -> ( image.id, NotStarted ))
        --                 |> List.append model.jobs
        --                 |> maybeStartJobs
        --     in
        --     ( { model
        --         | images = model.images ++ newImages
        --         , jobs = updatedJobs
        --       }
        --     , cmd
        --     )
        FileListReturned fileListJson ->
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
                        |> Debug.log "images"
              }
            , Cmd.none
            )



-- PORTS


port portJobFromElm : Job -> Cmd msg


port portJobToElm : (JD.Value -> msg) -> Sub msg


port portFilesFromElm : JD.Value -> Cmd msg


port portFilesToElm : (JD.Value -> msg) -> Sub msg



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ portJobToElm JobFinished
        , portFilesToElm FileListReturned
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



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ class "gallery-container"
        ]
        [ h2 [] [ text "gallery" ]
        , viewThumbnails model.images
        , div [ class "btn" ]
            [ fileUploadBtn [ onFilesUploaded FileListChosen ] []
            ]
        ]



-- probably need to manually have a hidden <input type=file multiple> so i can have a custom handler that keeps the native JS File obj around, for the sake of blob urls or whatever
-- e.target.files = FileList
-- e.target.files[0] = {lastModified=1690..., lastModifiedDate=Date, name="filename", path="some/path/filenname", size=12345..., type="mime/something"}


onFilesUploaded : (JD.Value -> Msg) -> Html.Attribute Msg
onFilesUploaded callbackMsg =
    -- an attribute, like onClick
    -- param is a message that holds a generic JD.Value type so it can be sent over port
    -- eg. onFilesUploaded MyMsg, where MyMsg is defined as MyMsg Json.Value
    -- the Json.Value is a FileList in javascript
    --
    -- note how json.map works:
    -- json.map : (a -> val) -> Decoder a -> Decoder val
    -- so it expects a function that returns a val, and returns a deocder that returns that val, and there's a middle type in common
    on "change" (JD.map callbackMsg (JD.at [ "target", "files" ] JD.value))


fileUploadBtn : List (Html.Attribute Msg) -> List (Html Msg) -> Html Msg
fileUploadBtn attributes children =
    div [ class "btn" ]
        [ input
            ([ type_ "file", multiple True ] ++ attributes)
            children
        ]


viewThumbnails : List Image -> Html Msg
viewThumbnails images =
    -- start with images,
    -- then images become last argument to list.map, resulting in list of thumbnailViews,
    -- then list of thumbnailViews become last argument (aka children) to div []
    images
        |> List.map (\image -> viewThumbnail image)
        -- images
        |> div
            [ class "gallery" -- single-row"
            ]



-- [ thumbnails ]


noneAttribute : Html.Attribute msg
noneAttribute =
    Html.Attributes.classList []


viewThumbnail : Image -> Html Msg
viewThumbnail image =
    div [ class "img-container" ]
        [ img
            [ case image.status of
                Loaded src_ ->
                    src src_

                NotLoaded ->
                    noneAttribute
            ]
            []
        , p [] [ text image.description ]
        , Html.map  -- whatever the final arg (node) produces, map it to something else instead
            (\_ -> RemovePicture image.id)
            (button
                [ class "delete-btn", onClick () ]
                [ text "X" ]
            )
        ]

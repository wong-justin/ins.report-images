port module Main exposing (..)

import Browser
import Dict exposing (Dict)
import File exposing (File)
import File.Select
import Html exposing (Html, button, div, h2, img, input, p, text)
import Html.Attributes exposing (class, multiple, src, style, type_)
import Html.Events exposing (on, onClick)
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


type alias Job =
    ( JobID, JobStatus )


type alias JobID =
    ImageID


type JobStatus
    = Started
    | NotStarted


type alias ImageURL =
    String



-- bloburl or asset path or something


type alias ImageID =
    String


type alias Image =
    { id : ImageID
    , description : String
    , status : ImageStatus
    }


type ImageStatus
    = Loaded ImageURL
    | NotLoaded


type CompressResults
    = Success ImageURL
    | Failure


type CompressMsg
    = SendCompress ImageURL
    | RecievedCompress CompressResults


init : () -> ( Model, Cmd Msg )
init _ =
    ( { images =
            [ { status = Loaded "../assets/400x128.jpg", description = "lorem ipsum lorem ipsum", id = "0" }
            , { status = Loaded "../assets/128x128.jpg", description = "lorem ipsum lorem ipsum", id = "1" }
            , { status = Loaded "../assets/128x400.jpg", description = "lorem ipsum lorem ipsum", id = "2" }
            , { status = NotLoaded, description = "hasn't been loaded yet", id = "3" }
            ]
      , jobs = []
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = Noop
    | OpenImagePicker
    | ImagesUploaded File (List File) -- weird return type from elm people: first file, and other files if they exist (instead of just a list in the first place)
    | JobFinished JobID
    | FileListChosen JD.Value
    | FileListReturned JD.Value



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

        OpenImagePicker ->
            ( model, File.Select.files [ "image/*" ] ImagesUploaded )

        -- TODO: use ports to get Blob urls from Files, since elm hides the useful aspects of web/js Blob and File objects that i need, aka URL.createObjectURL(blob/file)
        ImagesUploaded file remainingFiles ->
            let
                newImages =
                    uniteUploads file remainingFiles
                        |> List.map imageFromFile

                maybeStartJobs : List Job -> ( List Job, Cmd Msg )
                maybeStartJobs jobs =
                    case jobs of
                        -- there's at least one existing job and none are started because first isnt started
                        -- so update it and start the side effect
                        ( jobID, NotStarted ) :: remaining ->
                            ( ( jobID, Started ) :: remaining
                            , portJobFromElm jobID
                            )

                        -- else there are already pending jobs, so do nothing
                        _ ->
                            ( jobs, Cmd.none )

                ( updatedJobs, cmd ) =
                    newImages
                        |> List.map (\image -> ( image.id, NotStarted ))
                        |> List.append model.jobs
                        |> maybeStartJobs
            in
            ( { model
                | images = model.images ++ newImages
                , jobs = updatedJobs
              }
            , cmd
            )

        FileListChosen fileListJson ->
            ( model, portFilesFromElm fileListJson )

        FileListReturned fileListJson ->
            let
                filepathDecoder : JD.Decoder String
                filepathDecoder =
                    JD.field "url" JD.string

                imageDecoder : JD.Decoder Image
                imageDecoder =
                    -- id, description, status
                    JD.map3 Image
                        filepathDecoder
                        filepathDecoder
                        (JD.map (\filepath -> Loaded filepath) filepathDecoder)

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

                                    Err decodeErr ->
                                        decodeErr
                                        |> Debug.log "Image decoding error"
                                        |> (\_ -> [])
                           )
            in
            ( { model | images = model.images ++ newImages }, Cmd.none )

        JobFinished jobID ->
            let
                updatedJobs =
                    case model.jobs of
                        x :: xs ->
                            xs

                        _ ->
                            -- if job from port no longer exists in elm, then oh well, do nothing
                            model.jobs

                -- updatedImages = model.images -- TODO: update image src or whatever when given from port
            in
            ( { model
                | jobs = updatedJobs

                -- , images = updatedImages
              }
            , Cmd.none
            )



-- PORTS


port portJobFromElm : JobID -> Cmd msg


port portJobToElm : (JobID -> msg) -> Sub msg


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
-- FromElmStartJob -> let jobID = jobs.startNext; port.fromElm { process jobID }
-- ToElmFinishJob finishedJobID -> jobs.finish finishedJobID (may send startjob msg automatically)
-- startNextJob : JobQueue -> JobQueue Msg
-- startNextJob jobs =
--         let
--             firstJob = Dict.get jobs.rootID jobs.all
--         in
--                 Dict.update jobs.rootID (\mJob -> case mJob of
--                         Nothing ->
--         { queue |
--
-- finishJob : JobQueue -> JobID -> JobQueue Msg
--
-- addJobs : JobQueue -> JobQueue -> JobQueue Msg
--
-- removeJobs : JobQueue -> Set JobID -> JobQueue
-- iterateStaggeredTuples : List a -> List ( a, Maybe a )
-- iterateStaggeredTuples list =
--     -- [a,b,c,d] ->
--     -- [(a,Just b),(b,Just c),(c,Just d),(d,Nothing)]
--     let
--         listA =
--             list
--
--         listB =
--             list
--                 |> List.map (\x -> Just x)
--                 |> List.drop 1
--                 |> List.append [ Nothing ]
--     in
--     List.map2 Tuple.pair listA listB


addFilesToImages : List Image -> List File -> List Image
addFilesToImages existingImages newFiles =
    newFiles
        |> List.map (\file -> imageFromFile file)
        |> List.append existingImages



-- reduce by comparing prev,next with max fn, and initializing accumulator as fake id -1
-- TODO: better id generation, maybe with hash of blob, or maybe blob url for everything


createID : File -> String
createID file =
    File.name file


imageFromFile : File -> Image
imageFromFile file =
    { description = createID file
    , id = createID file
    , status = NotLoaded
    }


uniteUploads : File -> List File -> List File
uniteUploads file remainingFiles =
    file :: remainingFiles



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ class "gallery-container"
        ]
        [ h2 [] [ text "gallery" ]
        , viewThumbnails model.images
        , div [ class "btn" ]
            [ button [ onClick OpenImagePicker ] [ text "drag n drop or upload images" ]
            ]
        , fileUploadBtn [ onFilesUploaded FileListChosen ] []
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
            [ style "display" "flex"
            , style "flex-direction" "row"
            , class "gallery" -- single-row"
            ]



-- [ thumbnails ]


noneAttribute : Html.Attribute msg
noneAttribute =
    Html.Attributes.classList []


viewThumbnail : Image -> Html Msg
viewThumbnail image =
    div [ class "img-container" ]
        [ p [] [ text image.description ]
        , img
            [ case image.status of
                Loaded src_ ->
                    src src_

                NotLoaded ->
                    noneAttribute
            ]
            []
        ]

module Main exposing (..)

import Browser
import Dict exposing (Dict)
import File exposing (File)
import File.Select
import Html exposing (Html, button, div, h2, img, p, text)
import Html.Attributes exposing (class, src, style)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Html.Lazy exposing (lazy)
import Json.Decode.Pipeline


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }



-- MODEL


type alias Model =
    { images : List Image
    , jobs : Jobs
    }


-- example initial job queue:
-- {a: started, b} root
-- {b: notstarted, c}
-- {c: notstarted, d}
-- {d: notstarted, e}
-- {e: notstarted, none}
-- 
-- if user cancels jobs c (deleting unstarted job(s) in middle)
-- {a: started, b} root
-- {b: notstarted, d}
-- {d: notstarted, e}
-- {e: notstarted, none}
-- 
-- if user cancels pending job a and other job b (a remains because repsponse will come and delete `a` at that time. next available job is started):
-- {a: started, none}
-- {d: started, e} root
-- {e: notstarted, none}
-- 
-- if job d finishes next:
-- {a: started, none}
-- {e: started, none} root
--
-- if job e finishes next, a still not done yet:
-- {a : started, none}
-- no root
--
-- if user adds new jobs (dict union?):
-- {a : waitingtodie, none}
-- {f: started, g} root
-- {g: notstarted, h}
-- {h: notstarted, none}
-- 
-- so...
-- * typically only one job pending at a time
--   * but can be more than one if a started job is cancelled
--   * but only one job should be pending and have a queue (the 'root' node, until the last job has no more queued)
-- * traversing linked list necessary
-- * started jobs go out the port, async, no order
-- * finished job notifications come from the port, async, no order
-- * started jobs should have no ancestors (ie. no other node should have a started node as next)
-- * ACTUALLY no need to keep zombie jobs



type alias Jobs =
    Dict JobID {status: JobStatus, next: Maybe JobID}

type alias JobID =
    ImageID

type JobStatus = Started | NotStarted



-- type alias Job =
--     { curr : ImageID
--     , next : Maybe ImageID
--     }


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
      , jobs = Dict.empty
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = Noop
    | OpenImagePicker
    | ImagesUploaded File (List File) -- weird return type from elm people: first file, and other files if they exist (instead of just a list in the first place)
    | CancelJob JobID -- remove job from linked list if job is still pending (ie. exists)
    | DeleteImage ImageID -- remove image with this id from list model.images
    | FromElmStartJob JobID -- send async task in this linked list over port
    | ToElmFinishJob CompressResults -- show finished image element, and start next job



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
                files =
                    uniteUploads file remainingFiles

                newImages =
                    List.map imageFromFile files

                newJobs =
                    createJobs newImages
            in
            ( { model
                | images = List.append model.images newImages
                , jobs = Dict.union model.jobs newJobs
              }
            , Cmd.none
              -- , Ports.Out ImagePlaceholders
            )

        FromElmStartJob -> let jobID = jobs.startNext; port.fromElm { process jobID }
        ToElmFinishJob finishedJobID -> jobs.finish finishedJobID (may send startjob msg automatically)


createJobs : List Image -> Jobs
createJobs images =
    images
        |> List.map (\image -> image.id)
        |> iterateStaggeredTuples
        |> Dict.fromList

joinJobs : Jobs -> Jobs -> Jobs
joinJobs existing new


iterateStaggeredTuples : List a -> List ( a, Maybe a )
iterateStaggeredTuples list =
    -- [a,b,c,d] ->
    -- [(a,Just b),(b,Just c),(c,Just d),(d,Nothing)]
    let
        listA =
            list

        listB =
            list
                |> List.map (\x -> Just x)
                |> List.drop 1
                |> List.append [ Nothing ]
    in
    List.map2 Tuple.pair listA listB


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
    div [ class "gallery-container" ]
        [ h2 [] [ text "gallery" ]
        , viewThumbnails model.images
        , div [ class "btn" ]
            [ button [ onClick OpenImagePicker ] [ text "drag n drop or upload images" ]
            ]
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
            , class "gallery single-row"
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

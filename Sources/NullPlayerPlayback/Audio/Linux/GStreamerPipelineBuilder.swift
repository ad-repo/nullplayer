#if os(Linux)
import Foundation
import CGStreamer

enum GStreamerPipelineBuilderError: Error {
    case failedToCreateElement(factory: String)
    case failedToLink(String)
    case failedToCreateGhostPad
    case failedToBuildOutputBin
    case failedToParseCaps
}

struct GStreamerPipeline {
    let playbin: UnsafeMutablePointer<GstElement>
    let outputBin: UnsafeMutablePointer<GstElement>
    let equalizer: UnsafeMutablePointer<GstElement>
    let volume: UnsafeMutablePointer<GstElement>
    let appSink: UnsafeMutablePointer<GstElement>
    var outputSink: UnsafeMutablePointer<GstElement>
}

enum GStreamerPipelineBuilder {
    static func build(outputSinkFactory: String = "autoaudiosink", eqBandCount: Int = 10) throws -> GStreamerPipeline {
        let playbin = try makeElement(factory: "playbin3", name: "np_playbin")
        let outputBin = gst_bin_new("np_audio_sink_bin")
        guard let outputBin else {
            throw GStreamerPipelineBuilderError.failedToBuildOutputBin
        }

        let convert = try makeElement(factory: "audioconvert", name: "np_convert")
        let resample = try makeElement(factory: "audioresample", name: "np_resample")
        let equalizer = try makeElement(factory: "equalizer-nbands", name: "np_equalizer")
        let tee = try makeElement(factory: "tee", name: "np_tee")

        let sinkQueue = try makeElement(factory: "queue", name: "np_sink_queue")
        let volume = try makeElement(factory: "volume", name: "np_volume")
        let outputSink = try makeElement(factory: outputSinkFactory, name: "np_output_sink")

        let analysisQueue = try makeElement(factory: "queue", name: "np_analysis_queue")
        let appSink = try makeElement(factory: "appsink", name: "np_analysis_sink")

        _ = gst_bin_add(asBin(outputBin), convert)
        _ = gst_bin_add(asBin(outputBin), resample)
        _ = gst_bin_add(asBin(outputBin), equalizer)
        _ = gst_bin_add(asBin(outputBin), tee)
        _ = gst_bin_add(asBin(outputBin), sinkQueue)
        _ = gst_bin_add(asBin(outputBin), volume)
        _ = gst_bin_add(asBin(outputBin), outputSink)
        _ = gst_bin_add(asBin(outputBin), analysisQueue)
        _ = gst_bin_add(asBin(outputBin), appSink)

        setIntProperty(equalizer, name: "num-bands", value: Int32(max(1, eqBandCount)))

        setBoolProperty(appSink, name: "emit-signals", value: false)
        setBoolProperty(appSink, name: "sync", value: false)
        setIntProperty(appSink, name: "max-buffers", value: 4)
        setBoolProperty(appSink, name: "drop", value: true)

        guard let caps = gst_caps_from_string("audio/x-raw,format=F32LE,layout=interleaved,channels=2") else {
            throw GStreamerPipelineBuilderError.failedToParseCaps
        }
        setPointerProperty(appSink, name: "caps", pointer: UnsafeMutableRawPointer(caps))
        gst_caps_unref(caps)

        guard gst_element_link(convert, resample) != 0,
              gst_element_link(resample, equalizer) != 0,
              gst_element_link(equalizer, tee) != 0 else {
            throw GStreamerPipelineBuilderError.failedToLink("convert/resample/equalizer/tee")
        }

        guard gst_element_link(tee, sinkQueue) != 0,
              gst_element_link(sinkQueue, volume) != 0,
              gst_element_link(volume, outputSink) != 0 else {
            throw GStreamerPipelineBuilderError.failedToLink("sink branch")
        }

        setIntProperty(analysisQueue, name: "leaky", value: 2) // downstream
        setIntProperty(analysisQueue, name: "max-size-buffers", value: 2)

        guard gst_element_link(tee, analysisQueue) != 0,
              gst_element_link(analysisQueue, appSink) != 0 else {
            throw GStreamerPipelineBuilderError.failedToLink("analysis branch")
        }

        guard let sinkPad = gst_element_get_static_pad(convert, "sink") else {
            throw GStreamerPipelineBuilderError.failedToCreateGhostPad
        }
        guard let ghostPad = gst_ghost_pad_new("sink", sinkPad) else {
            gst_object_unref(UnsafeMutableRawPointer(sinkPad))
            throw GStreamerPipelineBuilderError.failedToCreateGhostPad
        }
        gst_object_unref(UnsafeMutableRawPointer(sinkPad))

        guard gst_element_add_pad(outputBin, ghostPad) != 0 else {
            gst_object_unref(UnsafeMutableRawPointer(ghostPad))
            throw GStreamerPipelineBuilderError.failedToCreateGhostPad
        }

        setPointerProperty(playbin, name: "audio-sink", pointer: UnsafeMutableRawPointer(outputBin))

        return GStreamerPipeline(
            playbin: playbin,
            outputBin: outputBin,
            equalizer: equalizer,
            volume: volume,
            appSink: appSink,
            outputSink: outputSink
        )
    }

    static func rebuildOutputSink(in pipeline: inout GStreamerPipeline, outputSinkFactory: String) throws {
        var currentState: GstState = GST_STATE_NULL
        _ = gst_element_get_state(pipeline.playbin, &currentState, nil, 0)
        _ = gst_element_set_state(pipeline.playbin, GST_STATE_PAUSED)

        _ = gst_element_set_state(pipeline.outputSink, GST_STATE_NULL)
        _ = gst_bin_remove(asBin(pipeline.outputBin), pipeline.outputSink)

        let nextSink = try makeElement(factory: outputSinkFactory, name: "np_output_sink_dynamic")
        _ = gst_bin_add(asBin(pipeline.outputBin), nextSink)

        guard gst_element_link(pipeline.volume, nextSink) != 0 else {
            throw GStreamerPipelineBuilderError.failedToLink("volume -> \(outputSinkFactory)")
        }

        pipeline.outputSink = nextSink
        _ = gst_element_sync_state_with_parent(nextSink)

        _ = gst_element_set_state(pipeline.playbin, currentState)
    }

    private static func makeElement(factory: String, name: String) throws -> UnsafeMutablePointer<GstElement> {
        guard let element = gst_element_factory_make(factory, name) else {
            throw GStreamerPipelineBuilderError.failedToCreateElement(factory: factory)
        }
        return element
    }

    private static func asBin(_ element: UnsafeMutablePointer<GstElement>) -> UnsafeMutablePointer<GstBin> {
        UnsafeMutableRawPointer(element).assumingMemoryBound(to: GstBin.self)
    }

    private static func setBoolProperty(_ element: UnsafeMutablePointer<GstElement>, name: String, value: Bool) {
        setIntProperty(element, name: name, value: value ? 1 : 0)
    }

    private static func setIntProperty(_ element: UnsafeMutablePointer<GstElement>, name: String, value: Int32) {
        name.withCString { propName in
            g_object_set(UnsafeMutableRawPointer(element), propName, value, nil)
        }
    }

    private static func setPointerProperty(_ element: UnsafeMutablePointer<GstElement>, name: String, pointer: UnsafeMutableRawPointer?) {
        name.withCString { propName in
            g_object_set(UnsafeMutableRawPointer(element), propName, pointer, nil)
        }
    }
}
#endif

import AVFoundation
import Foundation
import Observation
import Speech

/// 端上中文转写：SFSpeechRecognizer + AVAudioEngine。
/// 只把文字交给上层；音频不出设备（是否允许云端识别由系统设置决定）。
@MainActor
@Observable
final class SpeechTranscriber {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var errorText: String?
    private(set) var authorized = false

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    var isAvailable: Bool { recognizer?.isAvailable == true }

    func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        authorized = speech && mic
        if !authorized {
            errorText = speech ? "没有麦克风权限" : "没有语音识别权限"
        }
        return authorized
    }

    func start() async {
        guard !isRecording else { return }
        if !authorized, await requestPermission() == false { return }

        transcript = ""
        errorText = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.request = request
            isRecording = true

            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.stop() }
                    }
                    if let error {
                        self.errorText = "识别中断：\(error.localizedDescription)"
                        self.stop()
                    }
                }
            }
        } catch {
            errorText = "录音启动失败：\(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard isRecording || engine != nil else { return }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        stop()
        transcript = ""
        errorText = nil
    }
}

import AVFoundation
import Foundation
import Speech

/// 自检：拿打包进来的中文音频，走一遍 SFSpeechRecognizer。
/// 用来验证「中文识别器 + 权限 + 结果回收」这条链路，不依赖真人说话。
enum SpeechFileCheck {
    static func run() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        NSLog("[ASR] 授权状态=\(status.rawValue) (3=authorized)")
        guard status == .authorized else {
            NSLog("[ASR] 未授权，跳过识别")
            return
        }

        guard let url = Bundle.main.url(forResource: "voice-sample", withExtension: "m4a") else {
            NSLog("[ASR] 找不到打包的音频")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) else {
            NSLog("[ASR] zh-CN 识别器不可用")
            return
        }
        NSLog("[ASR] 识别器可用=\(recognizer.isAvailable) 端上支持=\(recognizer.supportsOnDeviceRecognition)")

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        do {
            let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result, result.isFinal {
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
            NSLog("[ASR] 识别结果=\(text)")
        } catch {
            NSLog("[ASR] 识别失败: \(error)")
        }
    }
}

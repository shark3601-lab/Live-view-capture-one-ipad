// CaptureProbe — test della sezione 6 bis.
//
// Verifica se ScreenCaptureKit riceve fotogrammi da una finestra (di solito il
// Live View di Capture One) quando è su un altro Space, coperta, ridotta nel
// Dock o su un altro display. Stampa una riga al secondo: si sposta la finestra
// tra gli scenari e si guarda cosa succede.
//
// Uso:
//   swift run -c release CaptureProbe list            elenca tutte le finestre
//   swift run -c release CaptureProbe watch [ID] [--fps 30]

import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

// MARK: - Conteggio fotogrammi

final class FrameCounter: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Snapshot {
        var complete = 0, idle = 0, blank = 0, suspended = 0, other = 0
        var changed = 0
        var width = 0, height = 0
        var stopError: Error?
    }

    private let lock = NSLock()
    private var current = Snapshot()
    private var lastHash: UInt64 = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return }

        // L'hash si calcola fuori dal lock: è il lavoro più lungo.
        var hash: UInt64?
        var size = (0, 0)
        if status == .complete, let pb = sb.imageBuffer {
            hash = Self.sampleHash(pb)
            size = (CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
        }

        lock.lock(); defer { lock.unlock() }
        switch status {
        case .complete:
            current.complete += 1
            if let hash, hash != lastHash { current.changed += 1; lastHash = hash }
            (current.width, current.height) = size
        case .idle: current.idle += 1
        case .blank: current.blank += 1
        case .suspended: current.suspended += 1
        default: current.other += 1
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); current.stopError = error; lock.unlock()
    }

    /// Restituisce i contatori dell'ultimo secondo e li azzera (l'errore resta).
    func takeSnapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let s = current
        current = Snapshot(width: s.width, height: s.height, stopError: s.stopError)
        return s
    }

    func clearError() { lock.lock(); current.stopError = nil; lock.unlock() }

    /// Hash su una griglia 64x48 di pixel: basta per capire se l'immagine cambia
    /// (live view vivo) o è congelata, senza leggere tutto il fotogramma.
    static func sampleHash(_ pb: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0 }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        guard w > 1, h > 1 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for gy in 0..<48 {
            let row = base.advanced(by: (gy * (h - 1) / 47) * bpr).assumingMemoryBound(to: UInt32.self)
            for gx in 0..<64 {
                hash = (hash ^ UInt64(row[gx * (w - 1) / 63])) &* 0x100_0000_01b3
            }
        }
        return hash
    }
}

// MARK: - Utilità

func allWindows() async throws -> [SCWindow] {
    // onScreenWindowsOnly: false → include finestre su altri Space, coperte e ridotte.
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    return content.windows.filter { $0.windowLayer == 0 && $0.frame.width > 50 && $0.frame.height > 50 }
}

func isCaptureOne(_ w: SCWindow) -> Bool {
    let app = w.owningApplication
    return (app?.applicationName ?? "").localizedCaseInsensitiveContains("Capture One")
        || (app?.bundleIdentifier ?? "").localizedCaseInsensitiveContains("captureone")
}

/// Preferisce la finestra di Capture One col titolo "Live", altrimenti la più grande.
func defaultWindow(_ windows: [SCWindow]) -> SCWindow? {
    let c1 = windows.filter(isCaptureOne)
    if let live = c1.first(where: { ($0.title ?? "").localizedCaseInsensitiveContains("live") }) { return live }
    return c1.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
}

func describe(_ w: SCWindow) -> String {
    let app = w.owningApplication?.applicationName ?? "?"
    let title = w.title.map { $0.isEmpty ? "(senza titolo)" : $0 } ?? "(senza titolo)"
    return String(format: "%6u  %-22@  %-34@  %4.0fx%-4.0f  %@",
                  w.windowID, String(app.prefix(22)) as NSString, String(title.prefix(34)) as NSString,
                  w.frame.width, w.frame.height, (w.isOnScreen ? "visibile" : "NON visibile") as NSString)
}

func timestamp() -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
}

// MARK: - Comandi

func list() async throws {
    let windows = try await allWindows()
    print("    ID  App                     Titolo                              Dimensioni  Stato")
    for w in windows.sorted(by: { isCaptureOne($0) && !isCaptureOne($1) }) { print(describe(w)) }
    if let d = defaultWindow(windows) { print("\nFinestra predefinita per 'watch': \(d.windowID)") }
    else { print("\nNessuna finestra di Capture One trovata. Passa un ID a 'watch'.") }
}

func makeStream(for window: SCWindow, fps: Int, counter: FrameCounter, queue: DispatchQueue) async throws -> SCStream {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    let scale = CGFloat(filter.pointPixelScale)
    config.width = max(2, Int(filter.contentRect.width * scale))
    config.height = max(2, Int(filter.contentRect.height * scale))
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.queueDepth = 5
    config.showsCursor = false
    let stream = SCStream(filter: filter, configuration: config, delegate: counter)
    try stream.addStreamOutput(counter, type: .screen, sampleHandlerQueue: queue)
    try await stream.startCapture()
    return stream
}

func watch(windowID: CGWindowID?, fps: Int) async throws {
    let counter = FrameCounter()
    let queue = DispatchQueue(label: "probe.capture", qos: .userInteractive)

    let windows = try await allWindows()
    let chosen: SCWindow?
    if let windowID { chosen = windows.first { $0.windowID == windowID } } else { chosen = defaultWindow(windows) }
    guard let target = chosen else {
        print("Finestra non trovata. Usa 'list' per vedere gli ID."); return
    }
    let id = target.windowID
    print("Osservo la finestra \(id): \(target.owningApplication?.applicationName ?? "?") — \(target.title ?? "")")
    print("Ora prova gli scenari: altro Space, coperta, ridotta nel Dock, altro display. Ctrl-C per uscire.\n")
    print("ora       stato         complete  idle  blank  susp  diversi  risoluzione   note")

    var stream: SCStream? = try await makeStream(for: target, fps: fps, counter: counter, queue: queue)

    while true {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let s = counter.takeSnapshot()
        let window = try? await allWindows().first { $0.windowID == id }
        var note = ""

        if let err = s.stopError {
            note = "stream fermato: \(err.localizedDescription)"
            stream = nil
            counter.clearError()
        }
        if stream == nil, let window {
            // Riaggancio automatico quando la finestra ricompare.
            stream = try? await makeStream(for: window, fps: fps, counter: counter, queue: queue)
            note += stream == nil ? " riaggancio fallito" : " riagganciato"
        }
        if s.complete > 0 && s.changed == 0 { note += " CONGELATO (stessi pixel)" }
        if s.complete == 0 && s.idle == 0 && s.blank == 0 && s.suspended == 0 { note += " nessun fotogramma" }

        let state = window == nil ? "sparita" : (window!.isOnScreen ? "visibile" : "non visibile")
        print(String(format: "%@  %-12@  %8d  %4d  %5d  %4d  %7d  %5dx%-5d  %@",
                     timestamp() as NSString, state as NSString, s.complete, s.idle, s.blank, s.suspended,
                     s.changed, s.width, s.height, note.trimmingCharacters(in: .whitespaces) as NSString))
    }
}

// MARK: - Avvio

@main
struct CaptureProbe {
    static func main() async {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            print("""
            Serve il permesso di Registrazione schermo.
            Impostazioni di Sistema → Privacy e sicurezza → Registrazione schermo e audio:
            abilita il Terminale (o l'app da cui lanci il comando), poi riaprilo e rilancia.
            """)
            exit(1)
        }

        var args = Array(CommandLine.arguments.dropFirst())
        var fps = 30
        if let i = args.firstIndex(of: "--fps"), i + 1 < args.count, let v = Int(args[i + 1]) {
            fps = max(1, min(120, v)); args.removeSubrange(i...(i + 1))
        }

        do {
            switch args.first ?? "list" {
            case "list": try await list()
            case "watch": try await watch(windowID: args.dropFirst().first.flatMap { CGWindowID($0) }, fps: fps)
            default: print("Uso: CaptureProbe list | watch [ID] [--fps 30]")
            }
        } catch {
            print("Errore: \(error.localizedDescription)"); exit(1)
        }
    }
}

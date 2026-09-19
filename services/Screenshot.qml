pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config" as QsConfig
import "." as QsServices

// Screenshot/Screen Recording Service
Singleton {
    id: root
    
    property bool isRecording: false
    property string lastScreenshotPath: ""
    property string lastRecordingPath: ""
    property string screenshotsDir: QsConfig.Config.paths.screenshotsDir

    property string _slurpGeometry: ""
    property string _slurpStderr: ""
    property string _windowGeomText: ""
    property string _focusedOutput: ""
    
    Component.onCompleted: {
        // Create screenshots directory if it doesn't exist
        mkdirProc.running = true
    }
    
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.screenshotsDir]
    }
    
    function takeScreenshot(mode: string) {
        // mode: "screen", "window", "region"
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
        const filename = `screenshot-${timestamp}.png`
        const filepath = `${screenshotsDir}/${filename}`
        
        if (mode === "region") {
            // For region selection, use slurp to get geometry then grim to capture.
            // Guard: re-exec mataría al slurp ya abierto (SIGTERM) — ignorar doble clic.
            if (slurpProc.running) {
                QsServices.Logger.debug("Screenshot", "Region selection already in progress, ignoring")
                return
            }
            slurpProc.exec(["slurp"])
        } else if (mode === "screen") {
            // Capture entire screen
            screenshotProc.exec(["grim", filepath])
            root.lastScreenshotPath = filepath
        } else if (mode === "window") {
            // For active window, we need to use hyprctl to get window geometry
            // then use slurp with those coordinates
            windowGeomProc.exec(["sh", "-c", "hyprctl activewindow -j | jq -r '.at[0],.at[1],.size[0],.size[1]' | paste -sd ' '"])
        }
    }
    
    // Get region geometry with slurp.
    // slurp exit codes: 0 = selected, 1 = user cancelled (ESC / right-click),
    // 15 (SIGTERM) = killed, e.g. shell reloaded mid-selection.
    Process {
        id: slurpProc
        stdout: StdioCollector {
            onStreamFinished: root._slurpGeometry = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: root._slurpStderr = text.trim()
        }
        onExited: code => {
            const geometry = root._slurpGeometry
            const errText = root._slurpStderr
            root._slurpGeometry = ""
            root._slurpStderr = ""

            if (code === 15) {
                QsServices.Logger.warn("Screenshot", "slurp was killed (SIGTERM) — shell may have reloaded, ignoring")
                return
            }
            if (code !== 0) {
                if (errText !== "")
                    QsServices.Logger.error("Screenshot", `slurp failed (code ${code}): ${errText}`)
                else
                    QsServices.Logger.debug("Screenshot", `slurp cancelled by user (code ${code})`)
                notifyProc.exec(["notify-send", "-i", "camera", "Sin captura",
                    "Pulsa Región y ARRASTRA un rectángulo con el mouse (ESC cancela). Un clic solo no selecciona nada."])
                return
            }
            if (geometry === "") {
                notifyProc.exec(["notify-send", "-i", "camera", "Sin captura",
                    "Selección vacía: pulsa y ARRASTRA para marcar el área."])
                return
            }

            const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
            const filename = `screenshot-${timestamp}.png`
            const filepath = `${root.screenshotsDir}/${filename}`

            QsServices.Logger.debug("Screenshot", `Capturing region: ${geometry}`)
            screenshotProc.exec(["grim", "-g", geometry, filepath])
            root.lastScreenshotPath = filepath
        }
    }
    
    // Get active window geometry
    Process {
        id: windowGeomProc
        stdout: StdioCollector {
            onStreamFinished: root._windowGeomText = text.trim()
        }
        onExited: code => {
            const out = root._windowGeomText
            root._windowGeomText = ""

            if (code !== 0) {
                QsServices.Logger.error("Screenshot", `window geometry failed with code: ${code}`)
                return
            }
            if (out === "") {
                return
            }

            const parts = out.split(' ')
            if (parts.length !== 4) {
                QsServices.Logger.warn("Screenshot", `Unexpected window geometry format: ${out}`)
                return
            }

            const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
            const filename = `screenshot-${timestamp}.png`
            const filepath = `${root.screenshotsDir}/${filename}`
            const geometry = `${parts[0]},${parts[1]} ${parts[2]}x${parts[3]}`

            QsServices.Logger.debug("Screenshot", `Capturing window: ${geometry}`)
            screenshotProc.exec(["grim", "-g", geometry, filepath])
            root.lastScreenshotPath = filepath
        }
    }
    
    Process {
        id: screenshotProc
        onExited: code => {
            if (code === 0) {
                QsServices.Logger.info("Screenshot", `Saved: ${root.lastScreenshotPath}`)
                
                // Copy to clipboard using wl-copy with shell redirection
                var path = root.lastScreenshotPath
                clipboardProc.exec(["sh", "-c", "wl-copy < \"$1\"", "sh", path])
                
                notifyProc.exec([
                    "notify-send",
                    "-i", root.lastScreenshotPath,
                    "Screenshot captured",
                    `Saved and copied to clipboard`
                ])
            } else {
                QsServices.Logger.error("Screenshot", `Failed with code: ${code}`)
            }
        }
    }
    
    Process {
        id: clipboardProc
    }
    
    Process {
        id: notifyProc
    }
    
    function startRecording(mode = "area") {
        if (isRecording) return

        // mode "full": graba el monitor con foco de inmediato
        // mode "area" (default): pide selección con slurp, ESC cancela
        if (mode === "full") {
            focusedMonitorProc.exec(["sh", "-c", "hyprctl monitors -j | jq -r '.[] | select(.focused==1) | .name'"])
            return
        }
        // Guard: re-exec mataría al slurp ya abierto (SIGTERM) — ignorar doble clic.
        if (slurpRecordProc.running) {
            QsServices.Logger.debug("Screenshot", "Record area selection already in progress, ignoring")
            return
        }
        slurpRecordProc.exec(["slurp"])
    }

    // Monitor con foco: wf-recorder pide elegir salida si hay 2+ monitores,
    // por eso siempre pasamos -o explícito en modo full.
    Process {
        id: focusedMonitorProc
        stdout: StdioCollector {
            onStreamFinished: root._focusedOutput = text.trim()
        }
        onExited: code => {
            var output = root._focusedOutput
            root._focusedOutput = ""
            if (code !== 0 || output === "") {
                QsServices.Logger.warn("Screenshot", "Could not detect focused monitor, using eDP-1")
                output = "eDP-1"
            }
            _startRecorder("", output)
        }
    }

    function _startRecorder(geometry, output) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
        const filename = `recording-${timestamp}.mp4`
        const filepath = `${screenshotsDir}/${filename}`
        root.lastRecordingPath = filepath

        var args
        var label
        if (geometry !== "") {
            args = ["wf-recorder", "-g", geometry, "-f", filepath]
            label = `area ${geometry}`
        } else {
            // -o explícito: con 2+ monitores wf-recorder pregunta y falla sin TTY
            args = ["wf-recorder", "-o", output ?? "eDP-1", "-f", filepath, "-c", "h264_vaapi", "-d", "/dev/dri/renderD128"]
            label = `full (${output ?? "eDP-1"})`
        }

        recordProc.exec(args)

        root.isRecording = true
        QsServices.Logger.info("Screenshot", `Recording started (${label})`)
        notifyProc.exec([
            "notify-send",
            "-i", "video-x-generic",
            "Screen recording started",
            `${label} — press Stop to finish`
        ])
    }

    // Selección de área para grabación (slurp). ESC / código 1 = cancela el usuario.
    Process {
        id: slurpRecordProc
        stdout: StdioCollector {
            onStreamFinished: root._slurpGeometry = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: root._slurpStderr = text.trim()
        }
        onExited: code => {
            const geometry = root._slurpGeometry
            const errText = root._slurpStderr
            root._slurpGeometry = ""
            root._slurpStderr = ""

            if (code === 15) {
                QsServices.Logger.warn("Screenshot", "record slurp was killed (SIGTERM), ignoring")
                return
            }
            if (code !== 0 || geometry === "") {
                if (errText !== "")
                    QsServices.Logger.error("Screenshot", `record slurp failed (code ${code}): ${errText}`)
                else
                    QsServices.Logger.debug("Screenshot", `record area selection cancelled (code ${code})`)
                notifyProc.exec(["notify-send", "-i", "video-x-generic", "Sin grabación",
                    "Pulsa Record y ARRASTRA un rectángulo con el mouse (ESC cancela). Un clic solo no selecciona nada."])
                return
            }
            QsServices.Logger.debug("Screenshot", `Recording region: ${geometry}`)
            _startRecorder(geometry)
        }
    }
    
    Process {
        id: recordProc
        onExited: code => {
            root.isRecording = false
            if (code === 0) {
                QsServices.Logger.info("Screenshot", `Recording saved: ${root.lastRecordingPath}`)
                notifyProc.exec([
                    "notify-send",
                    "-i", "video-x-generic",
                    "Screen recording saved",
                    root.lastRecordingPath
                ])
            } else {
                QsServices.Logger.error("Screenshot", `Recording failed with code: ${code}`)
                notifyProc.exec([
                    "notify-send",
                    "-i", "dialog-error",
                    "Screen recording failed",
                    `wf-recorder exited with code ${code} — check Quickshell log`
                ])
            }
        }
    }
    
    function stopRecording() {
        if (!isRecording) return
        
        stopRecordProc.running = true
        // isRecording will be set to false when the recording process finishes
    }
    
    Process {
        id: stopRecordProc
        command: ["pkill", "-SIGINT", "wf-recorder"]
    }
    
    function openScreenshotsFolder() {
        openProc.exec(["xdg-open", screenshotsDir])
    }
    
    Process {
        id: openProc
    }
    
    function copyLastScreenshot() {
        if (!lastScreenshotPath) return

        var path = lastScreenshotPath
        copyProc.exec(["sh", "-c", "wl-copy < \"$1\"", "sh", path])
    }
    
    Process {
        id: copyProc
    }
    
    function deleteLastScreenshot() {
        if (!lastScreenshotPath) return
        
        deleteProc.exec(["rm", lastScreenshotPath])
    }
    
    Process {
        id: deleteProc
        onExited: code => {
            if (code === 0) {
                QsServices.Logger.info("Screenshot", `Deleted: ${root.lastScreenshotPath}`)
                root.lastScreenshotPath = ""
            }
        }
    }
}

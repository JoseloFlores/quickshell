pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config" as QsConfig
import "." as QsServices

// System updates service — Debian/APT pending-updates counter.
// Slow source (apt list takes seconds), so: cached value paints instantly,
// real check on start + every 20 min + on demand via refresh().
Singleton {
    id: root

    property int count: 0
    property bool checking: false
    property bool ready: false
    property string lastCheck: ""

    readonly property string cacheFile: `${Quickshell.env("HOME")}/.cache/quickshell-updates-count`

    Component.onCompleted: {
        readCacheProc.running = true
        checkTimer.start()
    }

    function refresh() {
        if (checkProc.running)
            return
        root.checking = true
        checkProc.running = true
    }

    function runUpgrade() {
        // Opens the configured terminal with an interactive upgrade.
        // Refresh afterwards so the pill clears once done.
        const term = QsConfig.Config.launcher.terminalCommand ?? ["foot"]
        Quickshell.execDetached(term.concat(["-e", "bash", "-c", "sudo apt update && sudo apt upgrade; echo '--- listo, ENTER para cerrar ---'; read; exec bash"]))
    }

    // --- cache: instant first paint --------------------------------------
    Process {
        id: readCacheProc
        command: ["cat", root.cacheFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim())
                if (!isNaN(n) && n >= 0)
                    root.count = n
            }
        }
    }

    Process {
        id: writeCacheProc
        running: false
    }

    // --- periodic + on-demand check --------------------------------------
    Timer {
        id: checkTimer
        interval: 20 * 60 * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: checkProc
        command: ["sh", "-c", "LC_ALL=C apt list --upgradable 2>/dev/null | grep -c upgradable || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._checkOutput = text.trim()
        }
        onExited: code => {
            root.checking = false
            const out = root._checkOutput
            root._checkOutput = ""

            if (code !== 0) {
                QsServices.Logger.warn("Updates", `check failed with code ${code}`)
                return
            }
            const n = parseInt(out)
            if (isNaN(n) || n < 0) {
                QsServices.Logger.warn("Updates", `unexpected check output: ${out}`)
                return
            }

            const prev = root.count
            root.count = n
            root.ready = true
            const now = new Date()
            root.lastCheck = Qt.formatTime(now, "hh:mm")

            // Persist for instant paint on next start (best effort, no log spam)
            var c = root.count
            var f = root.cacheFile
            writeCacheProc.exec(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", `${c}`, f])

            if (prev === 0 && n > 0) {
                notifyProc.exec([
                    "notify-send",
                    "-i", "system-software-update",
                    "Actualizaciones disponibles",
                    `${n} paquete${n === 1 ? "" : "s"} pendiente${n === 1 ? "" : "s"} — clic en la píldora para actualizar`
                ])
            }
            QsServices.Logger.debug("Updates", `count=${n}`)
        }
    }

    property string _checkOutput: ""

    Process {
        id: notifyProc
    }
}

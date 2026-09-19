pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool ready: false
    property bool muted: false
    property real volume: 0
    readonly property int percentage: Math.round(volume * 100)

    property bool sourceReady: false
    property bool sourceMuted: false
    property real sourceVolume: 0
    readonly property int sourcePercentage: Math.round(sourceVolume * 100)

    // Escritura coalescada: el scroll genera muchos ticks; se actualiza la
    // propiedad al instante (UI/OSD responden ya) y se escribe a PipeWire
    // como máximo una vez cada applyTimer.interval con el último valor.
    // -1 = sin escritura pendiente.
    property real _pendingVolume: -1

    Timer {
        id: applyTimer
        interval: 60
        onTriggered: {
            if (root._pendingVolume < 0)
                return
            const v = Math.max(0, Math.min(1.5, root._pendingVolume))
            root._pendingVolume = -1
            setVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(3)]
            setVolProc.running = true
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (!getSink.running)
                getSink.running = true
            if (!getSource.running)
                getSource.running = true
        }
    }

    Process {
        id: getSink
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                // Examples:
                // "Volume: 0.39"
                // "Volume: 0.39 [MUTED]"
                const m = s.match(/Volume:\s*([0-9.]+)/)
                if (m) {
                    const v = parseFloat(m[1])
                    if (!isNaN(v)) {
                        root.ready = true
                        root.volume = Math.max(0, Math.min(1.5, v))
                    }
                }
                root.muted = /\[MUTED\]/.test(s)
            }
        }
    }

    Process {
        id: getSource
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim()
                const m = s.match(/Volume:\s*([0-9.]+)/)
                if (m) {
                    const v = parseFloat(m[1])
                    if (!isNaN(v)) {
                        root.sourceReady = true
                        root.sourceVolume = Math.max(0, Math.min(1.5, v))
                    }
                }
                root.sourceMuted = /\[MUTED\]/.test(s)
            }
        }
    }

    function setVolume(newVolume) {
        const v = Math.max(0, Math.min(1.5, newVolume))
        // Optimista: la barra/OSD/sliders reaccionan en este frame.
        // El poll de 1s confirma y corrige si PipeWire clampó el valor.
        root.volume = v
        if (root.muted) {
            root.muted = false
            setMute(false)
        }
        root._pendingVolume = v
        applyTimer.restart()
    }

    function increaseVolume() {
        setVolume(volume + 0.05)
    }

    function decreaseVolume() {
        setVolume(volume - 0.05)
    }

    function setMute(m) {
        setMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", m ? "1" : "0"]
        setMuteProc.running = true
    }

    function toggleMute() {
        setMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        setMuteProc.running = true
    }

    function setSourceVolume(newVolume) {
        setSourceMute(false)
        setSourceVolProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", Math.max(0, Math.min(1.5, newVolume)).toFixed(3)]
        setSourceVolProc.running = true
    }

    function setSourceMute(m) {
        setSourceMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", m ? "1" : "0"]
        setSourceMuteProc.running = true
    }

    function toggleSourceMute() {
        setSourceMuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]
        setSourceMuteProc.running = true
    }

    Process { id: setVolProc; onExited: () => { if (!getSink.running) getSink.running = true } }
    Process { id: setMuteProc }
    Process { id: setSourceVolProc }
    Process { id: setSourceMuteProc }
}

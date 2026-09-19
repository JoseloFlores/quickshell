pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    
    property real brightness: 0.5
    property real maxBrightness: 1.0
    
    // Alias for easier access
    readonly property real level: brightness
    readonly property int percentage: Math.round(brightness * 100)
    
    property string _backlightDevice: ""
    readonly property string backlightPath: _backlightDevice !== "" ? `/sys/class/backlight/${_backlightDevice}/brightness` : ""
    readonly property string maxBrightnessPath: _backlightDevice !== "" ? `/sys/class/backlight/${_backlightDevice}/max_brightness` : ""
    
    property int currentValue: 0
    property int maxValue: 255

    // Escritura coalescada (igual que Audio): el scroll genera muchos ticks;
    // se actualiza la propiedad al instante (barra/OSD responden ya) y se
    // escribe al backlight como máximo una vez cada applyTimer.interval.
    // -1 = sin escritura pendiente.
    property real _pendingBrightness: -1

    Timer {
        id: applyTimer
        interval: 60
        onTriggered: {
            if (root._pendingBrightness < 0 || backlightPath === "")
                return
            const newValue = Math.max(0, Math.min(1, root._pendingBrightness))
            root._pendingBrightness = -1
            // Use brightnessctl when available (works for most backlight devices)
            // Fallback to sysfs write when brightnessctl isn't present.
            // Trailing cat lets us converge on the real applied value fast.
            const percent = Math.round(newValue * 100)
            const sysfsValue = Math.round(newValue * maxValue)
            const cmd = `brightnessctl set ${percent}% || echo ${sysfsValue} | sudo tee "${backlightPath}" >/dev/null; cat "${backlightPath}"`
            setBrightnessProcess.command = ["/bin/sh", "-c", cmd]
            setBrightnessProcess.running = true
        }
    }
    
    Component.onCompleted: {
        detectBacklightDevice()
        readMaxBrightness()
        readBrightness()
        updateTimer.start()
    }

    function detectBacklightDevice() {
        detectProc.running = true
    }
    
    function readMaxBrightness() {
        if (maxBrightnessPath === "") return
        maxBrightnessProcess.command = ["/bin/cat", maxBrightnessPath]
        maxBrightnessProcess.running = true
    }

    function readBrightness() {
        if (backlightPath === "") return
        brightnessProcess.command = ["/bin/cat", backlightPath]
        brightnessProcess.running = true
    }
    
    function setBrightness(value) {
        // Clamp between 0 and 1
        const newValue = Math.max(0, Math.min(1, value))

        if (backlightPath === "")
            return

        // Optimista: la barra/OSD/sliders reaccionan en este frame.
        // El trailing cat + el timer de 2s confirman el valor real aplicado.
        root.brightness = newValue
        root._pendingBrightness = newValue
        applyTimer.restart()
    }
    
    function increaseBrightness() {
        setBrightness(brightness + 0.05)
    }
    
    function decreaseBrightness() {
        setBrightness(brightness - 0.05)
    }
    
    // Read max brightness
    Process {
        id: detectProc
        command: ["/bin/sh", "-c", "ls -1 /sys/class/backlight 2>/dev/null | head -n 1"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const dev = text.trim()
                if (dev.length > 0) {
                    root._backlightDevice = dev
                } else {
                    root._backlightDevice = ""
                }

                readMaxBrightness()
                readBrightness()
            }
        }
    }

    Process {
        id: maxBrightnessProcess
        running: false
        
        stdout: SplitParser {
            onRead: data => {
                const value = parseInt(data.trim())
                if (!isNaN(value) && value > 0) {
                    maxValue = value
                }
            }
        }
    }
    
    // Read current brightness
    Process {
        id: brightnessProcess
        running: false
        
        stdout: SplitParser {
            onRead: data => {
                const value = parseInt(data.trim())
                if (!isNaN(value)) {
                    currentValue = value
                    brightness = maxValue > 0 ? value / maxValue : 0
                }
            }
        }
    }
    
    // Set brightness process.
    // Collects the trailing `cat` so the UI converges on the real applied
    // value without waiting for the 2s update timer.
    Process {
        id: setBrightnessProcess
        running: false

        stdout: SplitParser {
            onRead: data => {
                const value = parseInt(data.trim())
                if (!isNaN(value)) {
                    currentValue = value
                    brightness = maxValue > 0 ? value / maxValue : brightness
                }
            }
        }

        onExited: () => { if (!brightnessProcess.running) readBrightness() }
    }
    
    // Update timer - optimized interval
    Timer {
        id: updateTimer
        interval: 2000  // Reduced frequency from 1000ms to 2000ms (brightness changes infrequently)
        repeat: true
        triggeredOnStart: true  // Get immediate first read
        onTriggered: readBrightness()
    }
}

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "." as QsServices

// Calendar service — real events from the local Thunderbird cache
// (Google calendars synced by Thunderbird, offline-friendly).
// Exposes eventsByDate: { "YYYY-MM-DD": [{t, s, e, all}, ...] }.
Singleton {
    id: root

    property var eventsByDate: ({})
    property string status: "loading" // loading | ready | error
    property string errorMessage: ""

    // Consumer visibility control - set to false to pause polling when UI is hidden
    property bool pollingActive: true

    // Wide window so month navigation (±months) still shows dots.
    readonly property string windowFrom: {
        const d = new Date()
        d.setDate(d.getDate() - 120)
        return Qt.formatDate(d, "yyyy-MM-dd")
    }
    readonly property string windowTo: {
        const d = new Date()
        d.setDate(d.getDate() + 400)
        return Qt.formatDate(d, "yyyy-MM-dd")
    }

    function pad(n) {
        return (n < 10 ? "0" : "") + n
    }

    function dateKey(year, monthZeroBased, day) {
        return `${year}-${root.pad(monthZeroBased + 1)}-${root.pad(day)}`
    }

    function hasEvents(year, monthZeroBased, day) {
        const list = root.eventsByDate[root.dateKey(year, monthZeroBased, day)]
        return !!list && list.length > 0
    }

    function eventsForDay(year, monthZeroBased, day) {
        return root.eventsByDate[root.dateKey(year, monthZeroBased, day)] ?? []
    }

    function refresh() {
        fetchProc.running = true
    }

    Process {
        id: fetchProc

        running: true
        command: ["python3", `${Quickshell.env("HOME")}/quickshell/scripts/qs-calendar.py`,
                  "--from", root.windowFrom, "--to", root.windowTo]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.eventsByDate = parsed
                    root.status = "ready"
                    root.errorMessage = ""
                    QsServices.Logger.debug("Calendar", `Loaded ${Object.keys(parsed).length} days with events`)
                } catch (e) {
                    root.status = "error"
                    root.errorMessage = "parse"
                    QsServices.Logger.warn("Calendar", `Failed to parse qs-calendar.py output: ${e?.message ?? e}`)
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    QsServices.Logger.warn("Calendar", text.trim().slice(0, 300))
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.status = "error"
                QsServices.Logger.warn("Calendar", `qs-calendar.py exited code=${code}`)
            }
        }
    }

    Timer {
        interval: 900000 // Refresh every 15 minutes
        running: root.pollingActive
        repeat: true
        onTriggered: root.refresh()
    }
}

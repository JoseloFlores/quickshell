import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import "../../config" as QsConfig
import "../../services" as QsServices
import "../../components"
import "../controlcenter/components"

PanelWindow {
    id: root

    property bool shouldShow: false

    readonly property var config: QsConfig.Config
    readonly property var pywal: QsServices.Pywal
    readonly property var time: QsServices.Time
    readonly property var systemUsage: QsServices.SystemUsage
    readonly property var players: QsServices.Players
    readonly property var screenshot: QsServices.Screenshot
    readonly property var network: QsServices.Network
    readonly property var audio: QsServices.Audio
    readonly property var powerProfiles: QsServices.PowerProfiles
    readonly property var notifs: QsServices.Notifs
    readonly property var bluetooth: QsServices.Bluetooth
    readonly property var calendar: QsServices.Calendar
    readonly property var battery: UPower.displayDevice

    readonly property color cSurface: pywal.surfaceContainerHighest
    readonly property color cSurfaceContainer: pywal.surfaceContainerHigh
    readonly property color cSurfaceContainerHigh: pywal.surfaceContainerHigh
    readonly property color cPrimary: pywal.primary
    readonly property color cText: pywal.foreground
    readonly property color cSubText: pywal.onSurfaceMuted
    readonly property color cBorder: pywal.outlineVariant
    readonly property int batteryPercent: Math.round((battery?.percentage ?? 0) * 100)
    readonly property bool hasMedia: players?.active !== null
    readonly property var currentDate: time.date
    readonly property int currentMonth: currentDate.getMonth()
    readonly property int currentYear: currentDate.getFullYear()
    readonly property int currentDay: currentDate.getDate()
    readonly property var dayLabels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    // Month navigation: 0 = current month, +1 = next, -1 = previous
    property int monthOffset: 0
    // Selected day of the visible month (-1 = none)
    property int selectedDay: -1
    readonly property date visibleMonthDate: new Date(currentYear, currentMonth + monthOffset, 1)
    readonly property int shownMonth: visibleMonthDate.getMonth()
    readonly property int shownYear: visibleMonthDate.getFullYear()
    onMonthOffsetChanged: selectedDay = -1
    // Agenda: Thunderbird events for the selected day (max 3 shown)
    readonly property var agendaEvents: root.selectedDay > 0
        ? root.calendar.eventsForDay(root.shownYear, root.shownMonth, root.selectedDay)
        : []
    readonly property int agendaShown: Math.min(root.agendaEvents.length, 3)
    readonly property int agendaExtraH: root.selectedDay > 0
        ? (16 + 6 + root.agendaShown * 26 + Math.max(0, root.agendaShown - 1) * 6
           + (root.agendaEvents.length > 3 ? 22 : 0))
        : 0

    function openCalendarApp() {
        Quickshell.execDetached(["thunderbird", "-calendar"])
    }
    readonly property int calendarOffset: {
        const first = new Date(shownYear, shownMonth, 1).getDay()
        return (first + 6) % 7
    }
    readonly property int calendarDays: new Date(shownYear, shownMonth + 1, 0).getDate()
    readonly property var calendarCells: {
        const cells = []
        const prevMonthDays = new Date(shownYear, shownMonth, 0).getDate()
        for (let index = 0; index < 42; index++) {
            const dayNumber = index - calendarOffset + 1
            if (dayNumber < 1) {
                cells.push({ day: prevMonthDays + dayNumber, current: false, today: false })
            } else if (dayNumber > calendarDays) {
                cells.push({ day: dayNumber - calendarDays, current: false, today: false })
            } else {
                cells.push({ day: dayNumber, current: true, today: monthOffset === 0 && dayNumber === currentDay })
            }
        }
        return cells
    }

    function closeDashboard() {
        shouldShow = false
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    screen: Quickshell.screens[0]
    anchors {
        top: true
        left: true
    }
    margins {
        top: (config.bar.height ?? 34) + config.dashboard.margin
        left: Math.max(0, Math.round((screen.width - config.dashboard.width) / 2))
    }
    implicitWidth: config.dashboard.width
    implicitHeight: shouldShow || panel.opacity > 0 ? Math.min(config.dashboard.height, screen.height - margins.top - 24) : 0
    visible: config.dashboard.enabled && (shouldShow || panel.opacity > 0)
    color: "transparent"

    WlrLayershell.keyboardFocus: shouldShow ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    FocusScope {
        id: panel
        anchors.fill: parent
        property real revealOffset: shouldShow ? 0 : -18
        scale: shouldShow ? 1.0 : 0.975
        opacity: shouldShow ? 1.0 : 0.0
        focus: root.shouldShow
        transform: Translate { y: panel.revealOffset }

        Keys.onEscapePressed: root.closeDashboard()

        Behavior on scale {
            NumberAnimation { duration: 240; easing.bezierCurve: [0.22, 1.0, 0.36, 1.0] }
        }

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
        }

        Behavior on revealOffset {
            NumberAnimation { duration: 260; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0] }
        }

        AuroraSurface {
            anchors.fill: parent
            radius: 28
            color: root.cSurface
            strokeColor: root.cBorder
            accentColor: root.cPrimary
            elevation: 4
            highlighted: root.shouldShow

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: time.format("dddd")
                            font.family: QsConfig.Config.appearance.fontFamily
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            color: root.cText
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: time.format("MMMM d, yyyy  •  hh:mm")
                            font.family: QsConfig.Config.appearance.fontFamily
                            font.pixelSize: 12
                            color: root.cSubText
                        }
                    }

                    Item { Layout.fillWidth: true }

                    SummaryChip {
                        icon: root.notifs.unreadCount > 0 ? "󰂚" : "󰂜"
                        label: root.notifs.unreadCount > 0 ? `${root.notifs.unreadCount} unread` : "Inbox clear"
                        accent: root.cPrimary
                    }

                    SummaryChip {
                        icon: root.network.connected ? "󰖩" : "󰖪"
                        label: root.network.connected ? (root.network.ssid || "Wi‑Fi") : "Offline"
                        accent: root.network.connected ? pywal.info : root.cSubText
                    }

                    SummaryChip {
                        icon: root.bluetooth.connected ? "󰂱" : "󰂲"
                        label: root.bluetooth.connected ? (root.bluetooth.deviceName || "Bluetooth") : "Bluetooth"
                        accent: root.bluetooth.connected ? pywal.secondary : root.cSubText
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        spacing: 16

                        SurfaceCard {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 254 + root.agendaExtraH

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Calendar"
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: root.cText
                                    }
                                    Item { Layout.fillWidth: true }
                                    CalNavButton {
                                        navIcon: "󰅁"
                                        onNavigated: root.monthOffset--
                                    }
                                    Text {
                                        Layout.minimumWidth: 110
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Qt.formatDate(root.visibleMonthDate, "MMMM yyyy")
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 12
                                        color: root.cSubText
                                    }
                                    CalNavButton {
                                        navIcon: "󰅂"
                                        onNavigated: root.monthOffset++
                                    }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    columns: 7
                                    rowSpacing: 6
                                    columnSpacing: 6

                                    Repeater {
                                        model: root.dayLabels

                                        Text {
                                            id: dayHeader
                                            required property var modelData
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: dayHeader.modelData
                                            font.family: QsConfig.Config.appearance.fontFamily
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: root.cSubText
                                        }
                                    }

                                    Repeater {
                                        model: root.calendarCells

                                        Rectangle {
                                            id: dayCell
                                            required property var modelData
                                            readonly property bool isSelected: dayCell.modelData.current && dayCell.modelData.day === root.selectedDay
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.preferredHeight: 24
                                            radius: 12
                                            color: dayCell.isSelected
                                                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.32)
                                                : dayCell.modelData.today
                                                    ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.18)
                                                    : dayMouse.containsMouse && dayCell.modelData.current
                                                        ? Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.08)
                                                        : dayCell.modelData.current
                                                            ? "transparent"
                                                            : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.03)
                                            border.width: (dayCell.modelData.today || dayCell.isSelected) ? 1 : 0
                                            border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.36)

                                            Text {
                                                anchors.centerIn: parent
                                                anchors.verticalCenterOffset: dayCell.modelData.current && root.calendar.hasEvents(root.shownYear, root.shownMonth, dayCell.modelData.day) ? -2 : 0
                                                text: `${dayCell.modelData.day}`
                                                font.family: QsConfig.Config.appearance.fontFamily
                                                font.pixelSize: 11
                                                font.weight: (dayCell.modelData.today || dayCell.isSelected) ? Font.Bold : Font.Medium
                                                color: dayCell.modelData.current ? root.cText : root.cSubText
                                                opacity: dayCell.modelData.current ? 1.0 : 0.45
                                            }

                                            // Event dot for days with Thunderbird calendar events
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                anchors.bottomMargin: 4
                                                width: 4
                                                height: 4
                                                radius: 2
                                                color: root.cPrimary
                                                visible: dayCell.modelData.current && root.calendar.hasEvents(root.shownYear, root.shownMonth, dayCell.modelData.day)
                                            }

                                            MouseArea {
                                                id: dayMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: dayCell.modelData.current
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const d = dayCell.modelData.day
                                                    root.selectedDay = (root.selectedDay === d) ? -1 : d
                                                }
                                            }
                                        }
                                    }
                                }

                                // Agenda: Thunderbird events for the selected day
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: root.selectedDay > 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.selectedDay > 0
                                            ? (root.agendaEvents.length > 0
                                                ? `${Qt.formatDate(new Date(root.shownYear, root.shownMonth, root.selectedDay), "d MMM")} · ${root.agendaEvents.length}`
                                                : `${Qt.formatDate(new Date(root.shownYear, root.shownMonth, root.selectedDay), "d MMM")} · sin eventos`)
                                            : ""
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: root.cSubText
                                    }

                                    Repeater {
                                        model: root.agendaEvents.slice(0, 3)

                                        Rectangle {
                                            id: eventRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 26
                                            radius: 13
                                            color: eventMouse.containsMouse
                                                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.16)
                                                : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.04)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                Text {
                                                    Layout.preferredWidth: 62
                                                    elide: Text.ElideRight
                                                    text: eventRow.modelData.all ? "Todo el día" : (eventRow.modelData.s ?? "")
                                                    font.family: QsConfig.Config.appearance.fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                    color: root.cPrimary
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: eventRow.modelData.t ?? ""
                                                    font.family: QsConfig.Config.appearance.fontFamily
                                                    font.pixelSize: 11
                                                    color: root.cText
                                                }
                                            }

                                            MouseArea {
                                                id: eventMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.openCalendarApp()
                                            }
                                        }
                                    }

                                    Text {
                                        visible: root.agendaEvents.length > 3
                                        text: `+${root.agendaEvents.length - 3} más en Thunderbird`
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 11
                                        color: root.cPrimary

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openCalendarApp()
                                        }
                                    }
                                }
                            }
                        }

                        SurfaceCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 14

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Daily Controls"
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: root.cText
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: root.powerProfiles.isAvailable ? root.powerProfiles.getProfileLabel(root.powerProfiles.activeProfile) : "Power"
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 11
                                        color: root.cSubText
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    QuickAction {
                                        Layout.fillWidth: true
                                        icon: "󰄀"
                                        label: "Region"
                                        subLabel: "Screenshot"
                                        accent: root.cPrimary
                                        onClicked: root.screenshot.takeScreenshot("region")
                                    }
                                    QuickAction {
                                        Layout.fillWidth: true
                                        icon: root.screenshot.isRecording ? "󰛿" : "󰻃"
                                        label: root.screenshot.isRecording ? "Stop" : "Record"
                                        subLabel: "Screen"
                                        accent: pywal.error
                                        onClicked: {
                                            if (root.screenshot.isRecording)
                                                root.screenshot.stopRecording()
                                            else
                                                root.screenshot.startRecording()
                                        }
                                    }
                                    QuickAction {
                                        Layout.fillWidth: true
                                        icon: "󰆍"
                                        label: "Terminal"
                                        subLabel: "Foot"
                                        accent: pywal.secondary
                                        onClicked: Quickshell.execDetached(config.launcher.terminalCommand ?? ["foot"])
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: root.powerProfiles.availableProfiles

                                        Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36
                                            radius: 18
                                            color: root.powerProfiles.activeProfile === modelData
                                                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.16)
                                                : root.cSurfaceContainerHigh
                                            border.width: 1
                                            border.color: root.powerProfiles.activeProfile === modelData
                                                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.36)
                                                : Qt.rgba(root.cText.r, root.cText.g, root.cText.b, 0.05)

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.powerProfiles.getProfileLabel(modelData)
                                                font.family: QsConfig.Config.appearance.fontFamily
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: root.powerProfiles.activeProfile === modelData ? root.cPrimary : root.cText
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.powerProfiles.setProfile(modelData)
                                            }
                                        }
                                    }
                                }

                                SurfaceMetricRow {
                                    icon: "󰂎"
                                    title: "Battery"
                                    value: `${root.batteryPercent}%`
                                    detail: battery?.state === UPowerDevice.Charging ? "Charging" : battery?.state === UPowerDevice.FullyCharged ? "Full" : "Discharging"
                                    accent: root.batteryPercent <= 20 ? pywal.error : root.cPrimary
                                }
                                SurfaceMetricRow {
                                    icon: root.audio.muted ? "󰖁" : "󰕾"
                                    title: "Volume"
                                    value: `${Math.round((root.audio.percentage ?? 0))}%`
                                    detail: root.audio.muted ? "Muted" : "Default output"
                                    accent: pywal.secondary
                                }
                                SurfaceMetricRow {
                                    icon: root.network.connected ? "󰖩" : "󰖪"
                                    title: "Network"
                                    value: root.network.connected ? (root.network.ssid || "Connected") : "Disconnected"
                                    detail: root.network.connected ? `Signal ${root.network.signalStrength}%` : "Wi‑Fi idle"
                                    accent: pywal.info
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        spacing: 16

                        SystemStats {
                            Layout.fillWidth: true
                            systemUsage: root.systemUsage
                            pywal: root.pywal
                        }

                        SurfaceCard {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.hasMedia ? 124 : 88

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 0
                                spacing: 0

                                Text {
                                    visible: !root.hasMedia
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 22
                                    text: "No media playing"
                                    font.family: QsConfig.Config.appearance.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: root.cSubText
                                }

                                MediaCard {
                                    visible: root.hasMedia
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    mpris: root.players
                                    pywal: root.pywal
                                }
                            }
                        }

                        SurfaceCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Today at a Glance"
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: root.cText
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: root.time.format("ddd")
                                        font.family: QsConfig.Config.appearance.fontFamily
                                        font.pixelSize: 11
                                        color: root.cSubText
                                    }
                                }

                                InsightCard {
                                    title: "CPU and memory"
                                    body: `CPU ${Math.round((root.systemUsage.cpuPerc ?? 0) * 100)}% · RAM ${Math.round((root.systemUsage.memPerc ?? 0) * 100)}%`
                                    accent: pywal.error
                                }
                                InsightCard {
                                    title: "Network activity"
                                    body: `↓ ${Math.round((root.systemUsage.downloadSpeed ?? 0) / 1024)} KB/s · ↑ ${Math.round((root.systemUsage.uploadSpeed ?? 0) / 1024)} KB/s`
                                    accent: pywal.info
                                }
                                InsightCard {
                                    title: "Inbox status"
                                    body: root.notifs.unreadCount > 0
                                        ? `${root.notifs.unreadCount} unread notifications waiting`
                                        : "No unread notifications — you’re clear"
                                    accent: pywal.primary
                                }
                                InsightCard {
                                    title: "Power mode"
                                    body: root.powerProfiles.isAvailable
                                        ? `${root.powerProfiles.getProfileLabel(root.powerProfiles.activeProfile)} profile active`
                                        : "powerprofilesctl not available"
                                    accent: pywal.secondary
                                }
                                InsightCard {
                                    title: "Top processes"
                                    body: {
                                        var tops = root.systemUsage.topProcesses
                                        if (tops.length === 0) return "Collecting..."
                                        var lines = []
                                        for (var i = 0; i < Math.min(tops.length, 3); i++) {
                                            var p = tops[i]
                                            lines.push(p.name.substring(0, 20) + " " + Math.round(p.cpu) + "%")
                                        }
                                        return lines.join(" · ")
                                    }
                                    accent: pywal.warning
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component CalNavButton: Rectangle {
        id: navRoot
        required property string navIcon
        signal navigated()
        width: 26
        height: 26
        radius: 13
        color: navMouse.containsMouse ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.16) : "transparent"

        Text {
            anchors.centerIn: parent
            text: navRoot.navIcon
            font.family: "Material Design Icons"
            font.pixelSize: 16
            color: root.cSubText
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: navRoot.navigated()
        }
    }

    component SurfaceCard: Rectangle {
        radius: 22
        color: root.cSurfaceContainer
        border.width: 1
        border.color: root.cBorder
    }

    component SummaryChip: Rectangle {
        id: chipRoot
        required property string icon
        required property string label
        required property color accent
        // Fixed width + fill-anchored row + eliding label: every label length
        // fits by construction. (Width math off implicitWidth proved fragile:
        // a free RowLayout grants children their full implicit width, so
        // maximumWidth never constrained and the centered row spilled out.)
        width: 150
        height: 34
        radius: 17
        color: Qt.rgba(accent.r, accent.g, accent.b, 0.14)
        border.width: 1
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.18)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 6
            Text {
                text: chipRoot.icon
                font.family: "Material Design Icons"
                font.pixelSize: 15
                color: chipRoot.accent
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: chipRoot.label
                font.family: QsConfig.Config.appearance.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.cText
            }
        }
    }

    component QuickAction: Rectangle {
        id: actionRoot
        required property string icon
        required property string label
        required property string subLabel
        required property color accent
        signal clicked()

        radius: 18
        color: mouse.containsMouse ? Qt.lighter(root.cSurfaceContainerHigh, 1.03) : root.cSurfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(actionRoot.accent.r, actionRoot.accent.g, actionRoot.accent.b, 0.22)
        implicitHeight: 84
        scale: mouse.pressed ? 0.985 : mouse.containsMouse ? 1.01 : 1.0

        Behavior on scale {
            NumberAnimation { duration: 180; easing.bezierCurve: [0.22, 1.0, 0.36, 1.0] }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            Text {
                text: actionRoot.icon
                font.family: "Material Design Icons"
                font.pixelSize: 20
                color: actionRoot.accent
            }
            Text {
                text: actionRoot.label
                font.family: QsConfig.Config.appearance.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: root.cText
            }
            Text {
                text: actionRoot.subLabel
                font.family: QsConfig.Config.appearance.fontFamily
                font.pixelSize: 10
                color: root.cSubText
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionRoot.clicked()
        }
    }

    component SurfaceMetricRow: Rectangle {
        id: metricRoot
        required property string icon
        required property string title
        required property string value
        required property string detail
        required property color accent
        // Fill the parent column: without this the implicit width is 0 and
        // the inner row crams icon/column/value on top of each other.
        Layout.fillWidth: true
        radius: 16
        color: root.cSurfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(metricRoot.accent.r, metricRoot.accent.g, metricRoot.accent.b, 0.14)
        implicitHeight: 56

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: metricRoot.icon
                font.family: "Material Design Icons"
                font.pixelSize: 18
                color: metricRoot.accent
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: metricRoot.title
                    font.family: QsConfig.Config.appearance.fontFamily
                    font.pixelSize: 11
                    color: root.cSubText
                }
                Text {
                    text: metricRoot.detail
                    font.family: QsConfig.Config.appearance.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: root.cText
                }
            }
            Text {
                text: metricRoot.value
                font.family: QsConfig.Config.appearance.fontFamily
                font.pixelSize: 12
                font.weight: Font.Bold
                color: root.cText
            }
        }
    }

    component InsightCard: Rectangle {
        id: insightRoot
        required property string title
        required property string body
        required property color accent
        // Fill the parent column: without this the implicit width is 0 and
        // title/body stack on top of each other.
        Layout.fillWidth: true
        radius: 18
        color: root.cSurfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.18)
        // Adaptive height: fixed 74px clipped wrapped bodies ("Top processes",
        // long inbox/power lines), which then overlapped the card below.
        implicitHeight: insightCol.implicitHeight + 24

        ColumnLayout {
            id: insightCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: insightRoot.title
                font.family: QsConfig.Config.appearance.fontFamily
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: insightRoot.accent
            }
            Text {
                Layout.fillWidth: true
                text: insightRoot.body
                wrapMode: Text.WordWrap
                font.family: QsConfig.Config.appearance.fontFamily
                font.pixelSize: 11
                color: root.cText
            }
        }
    }
}
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../../services" as QsServices

// Updates pill — hidden when system is up to date.
// Click: open terminal with interactive upgrade. Wheel: force re-check.
Item {
    id: root

    property var barWindow

    readonly property var pywal: QsServices.Pywal
    readonly property var updates: QsServices.Updates
    readonly property bool isHovered: mouseArea.containsMouse

    readonly property int pending: updates.count
    readonly property bool active: updates.ready && pending > 0

    implicitWidth: active ? pillContent.implicitWidth + 18 : 0
    implicitHeight: 20

    visible: active
    opacity: active ? 1 : 0

    Behavior on implicitWidth {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        NumberAnimation { duration: 150 }
    }

    RowLayout {
        id: pillContent
        anchors.centerIn: parent
        spacing: 3

        Text {
            text: updates.checking ? "󰑐" : "󰚰"
            font.family: "Material Design Icons"
            font.pixelSize: 14
            color: isHovered ? pywal.primary : pywal.warning

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            // Spin while checking (rotation restarts each check)
            RotationAnimation on rotation {
                running: updates.checking
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1200
            }
        }

        Text {
            text: pending
            font.family: "Inter"
            font.pixelSize: 10
            font.weight: Font.Medium
            color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.7)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        ToolTip.visible: containsMouse
        ToolTip.delay: 300
        ToolTip.text: updates.checking
            ? "Revisando actualizaciones..."
            : `${pending} paquete${pending === 1 ? "" : "s"} pendiente${pending === 1 ? "" : "s"}` +
              (updates.lastCheck !== "" ? ` · rev. ${updates.lastCheck}` : "") +
              "\nClic: actualizar en terminal · Scroll: re-chequear"

        onClicked: root.updates.runUpgrade()
        onWheel: root.updates.refresh()
    }
}

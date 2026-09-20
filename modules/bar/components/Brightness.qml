import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services" as QsServices
import "../../../components/effects"

// Brightness indicator with number - no popup
Item {
    id: root
    
    property var barWindow
    
    readonly property var pywal: QsServices.Pywal
    readonly property var brightness: QsServices.Brightness
    readonly property bool isHovered: mouseArea.containsMouse
    readonly property int percentage: brightness.percentage
    
    implicitWidth: brightnessRow.implicitWidth
    implicitHeight: 20
    
    RowLayout {
        id: brightnessRow
        anchors.centerIn: parent
        spacing: 3
        
        // Brightness icon
        Text {
            id: brightnessIcon
            
            text: {
                if (percentage >= 75) return "󰃠"
                if (percentage >= 50) return "󰃟"
                if (percentage >= 25) return "󰃞"
                return "󰃝"
            }
            
            font.family: "Material Design Icons"
            font.pixelSize: 14
            
            color: {
                if (isHovered) return pywal.primary
                if (percentage >= 75) return Qt.rgba(pywal.warning.r, pywal.warning.g, pywal.warning.b, 0.85)
                return pywal.foreground
            }
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            
            scale: isHovered ? 1.05 : 1.0
            Behavior on scale {
                NumberAnimation { duration: 100 }
            }
        }
        
        // Percentage number
        Text {
            id: brightnessText
            
            text: percentage
            font.family: "Inter"
            font.pixelSize: 10
            font.weight: Font.Medium
            
            color: Qt.rgba(pywal.foreground.r, pywal.foreground.g, pywal.foreground.b, 0.7)
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
            
            // Number change animation
            Behavior on text {
                SequentialAnimation {
                    NumberAnimation {
                        target: brightnessText
                        property: "scale"
                        to: 1.15
                        duration: 80
                    }
                    NumberAnimation {
                        target: brightnessText
                        property: "scale"
                        to: 1.0
                        duration: 100
                    }
                }
            }
        }
    }
    
    // Interaction area
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        // Acumulador: una rueda entrega ~120 unidades por tick; un touchpad
        // entrega muchas fracciones pequeñas. Acumular da pasos proporcionales
        // en ambos casos en vez de un salto entero por evento mínimo.
        property real wheelAccum: 0

        onClicked: {
            // Click alterna entre brillo alto y bajo (la rueda ajusta fino)
            if (brightness.percentage >= 90)
                brightness.setBrightness(0.35)
            else
                brightness.setBrightness(1.0)
        }

        onWheel: wheel => {
            wheelAccum += wheel.angleDelta.y
            while (wheelAccum >= 120) {
                wheelAccum -= 120
                brightness.increaseBrightness()
            }
            while (wheelAccum <= -120) {
                wheelAccum += 120
                brightness.decreaseBrightness()
            }
        }
    }
    
    // Brightness change pulse
    Connections {
        target: brightness
        function onBrightnessChanged() {
            pulseAnim.restart()
        }
    }
    
    SequentialAnimation {
        id: pulseAnim
        
        NumberAnimation {
            target: brightnessIcon
            property: "scale"
            to: 1.2
            duration: 80
        }
        NumberAnimation {
            target: brightnessIcon
            property: "scale"
            to: isHovered ? 1.05 : 1.0
            duration: 120
        }
    }
}

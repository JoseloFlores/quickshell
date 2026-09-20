pragma Singleton

import Quickshell
import QtQuick
import "." as QsServices

// GamingMode: orquestador de rendimiento. No toca sysfs directamente;
// delega en PowerProfiles (power-profiles-daemon), IdleInhibitor y
// el mecanismo de holders de Notifs para el DND.
Singleton {
    id: root

    property bool enabled: false

    onEnabledChanged: {
        QsServices.Logger.info("GamingMode", `Gaming mode ${enabled ? "ENABLED" : "DISABLED"}`)

        if (enabled) {
            if (powerProfiles.isAvailable) {
                powerProfiles.setProfile("performance")
            } else {
                QsServices.Logger.warn("GamingMode", "powerprofilesctl not available, skipping CPU profile")
            }
            idleInhibitor.inhibited = true
            notifs.requestDnd("gaming")
        } else {
            if (powerProfiles.isAvailable) {
                powerProfiles.setProfile("balanced")
            }
            idleInhibitor.inhibited = false
            notifs.releaseDnd("gaming")
        }
    }

    function toggle() {
        enabled = !enabled
    }

    // Reference to services (will be set by Control Center)
    readonly property var notifs: QsServices.Notifs
    readonly property var powerProfiles: QsServices.PowerProfiles
    readonly property var idleInhibitor: QsServices.IdleInhibitor
}

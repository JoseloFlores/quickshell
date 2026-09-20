pragma Singleton

import Quickshell

Singleton {
    // Expone las claves reales de Config.appearance (ver Config.qml).
    // Antes exponía rounding/spacing/padding/font/anim/transparency,
    // que no existen en shell.json y resolvían a undefined.
    // Los tokens Material3 viven en AppearanceConfig.qml.
    readonly property string fontFamily: Config.appearance.fontFamily
    readonly property string materialIconFont: Config.appearance.materialIconFont
}

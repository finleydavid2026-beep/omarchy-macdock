import QtQuick
import Quickshell
import Quickshell.Io

// macOS-style dock.
//
// A floating, rounded, translucent panel at the bottom centre of the screen
// holding the user's apps. The signature behaviour is magnification: as the
// cursor moves across the dock, each icon scales up with a falloff based on
// its distance from the cursor, and lifts slightly, the way the macOS dock
// does. Clicking an icon launches the app.
//
// The dock is a bar widget rather than its own window: Omarchy's bar is
// already a bottom strip, so making its background transparent and putting the
// dock in the centre section gives the floating look without a second
// layer-shell surface (and without fighting the bar for input).
//
// The root is a plain Item carrying the three properties the bar host injects
// (`bar`, `moduleName`, `settings`). qs.Ui's BarWidget does not resolve from a
// third-party plugin's QML context, so these are declared by hand.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})

  readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy/macdock"
  readonly property string pinsPath: root.configDir + "/pins.json"

  // macOS dock proportions. The icon box is square; the panel padding around
  // it is what gives the dock its pill shape.
  readonly property int iconSize: 48
  readonly property int iconGap: 10
  readonly property int padX: 12
  readonly property int padY: 10
  readonly property int radius: 20

  // Magnification: the icon under the cursor reaches maxScale, and the effect
  // falls off to nothing at magRadius pixels away.
  readonly property real maxScale: 1.5
  readonly property real magRadius: 150

  // Cursor position in dock-local coordinates. -1 means "no cursor".
  property real cursorX: -1

  // System control icons tucked into the right end of the dock: network,
  // bluetooth, audio, power. They are smaller than the app icons and sit in
  // the same translucent panel, so the whole bar reads as one dock.
  readonly property int sysSize: 24
  readonly property int sysGap: 6
  readonly property int sysPadAfterApps: 10
  readonly property var sysControls: [
    { id: "network",  icon: "network-wireless-connected", cmd: "omarchy-shell shell toggle omarchy.network '{}'" },
    { id: "bluetooth",icon: "bluetooth",                 cmd: "omarchy-shell shell toggle omarchy.bluetooth '{}'" },
    { id: "audio",    icon: "audio-volume-high",          cmd: "omarchy-shell shell toggle omarchy.audio '{}'" },
    { id: "power",    icon: "battery",                    cmd: "omarchy-shell shell toggle omarchy.power '{}'" }
  ]

  implicitWidth: root.padX * 2
    + Math.max(1, root.slots.length) * (root.iconSize + root.iconGap) - root.iconGap
    + (root.slots.length > 0 ? root.sysPadAfterApps : 0)
    + root.sysControls.length * root.sysSize + (root.sysControls.length - 1) * root.sysGap
  implicitHeight: root.padY * 2 + Math.max(root.iconSize, root.sysSize)

  // [{ index, id, name, icon, source, running }]
  property var slots: []
  property var entryIndex: ({})

  // `bar` is injected after the first FileView load fires, so reload again once
  // the component is complete — otherwise the icons resolve against a null
  // app library and the dock comes up empty.
  Component.onCompleted: {
    var raw = ""
    try { raw = String(pinsFile.text ? pinsFile.text() : "") } catch (e) { raw = "" }
    root.reloadSlots(raw)
  }

  FileView {
    id: pinsFile
    path: root.pinsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadSlots(text())
    onLoadFailed: root.reloadSlots("")
    // `text()` is stale inside onFileChanged, so re-read and let onLoaded fire.
    onFileChanged: reload()
  }

  // The shell only hands `appLibrary` to plugins whose manifest declares the
  // "menu" kind, so a bar-widget gets null there. Use Quickshell's global
  // DesktopEntries instead — it carries the same entries (.id, .name, .icon,
  // .noDisplay) and is available to any plugin.
  function appEntries() {
    try { return DesktopEntries.applications.values || [] } catch (e) { return [] }
  }

  function iconFor(icon) {
    var value = String(icon || "")
    if (!value) return ""
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var found = Quickshell.iconPath(value, true)
    if (found && found.length > 0) return found
    return Quickshell.iconPath("application-x-executable", true) || ""
  }

  // A `class:org.foo.Bar` pin names a window class, not a desktop id, so it
  // has to be mapped back to an entry. Matching any dotted segment of the
  // class against the installed desktop ids covers the usual reverse-domain
  // naming (org.localsend.localsend_app -> localsend).
  function resolvePin(pin) {
    if (!pin) return ""
    if (pin.indexOf("class:") !== 0) return root.entryIndex[pin] ? pin : ""
    var parts = pin.slice(6).split(".")
    for (var i = 0; i < parts.length; i++) if (root.entryIndex[parts[i]]) return parts[i]
    return ""
  }

  function reloadSlots(rawText) {
    var raw = String(rawText || "")
    var ids = []
    try {
      var parsed = JSON.parse(raw || "[]")
      if (Array.isArray(parsed)) ids = parsed
    } catch (e) { ids = [] }

    // Index every installed desktop entry once, so a pin resolves to its name
    // and icon without a per-slot lookup.
    var index = ({})
    var entries = root.appEntries()
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e && e.id) index[String(e.id)] = e
    }
    root.entryIndex = index

    var next = []
    for (var s = 0; s < ids.length; s++) {
      var id = root.resolvePin(String(ids[s] || ""))
      var entry = index[id]
      next.push({
        index: s,
        id: id,
        name: entry ? String(entry.name || id) : id,
        icon: entry ? String(entry.icon || "") : "",
        source: entry ? root.iconFor(entry.icon) : ""
      })
    }
    root.slots = next
  }

  function togglePanel(cmd) {
    if (!cmd || !root.bar) return
    try { root.bar.run(cmd) } catch (e) { }
  }

  function launch(slot) {
    if (!slot || !slot.id) return
    var entries = root.appEntries()
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e && String(e.id) === slot.id && typeof e.execute === "function") {
        try { e.execute(); return } catch (err) { }
      }
    }
    if (root.bar) root.bar.run("gtk-launch " + root.bar.shellQuote(slot.id + ".desktop"))
  }

  // Magnification for the icon at slot centre x.
  function scaleFor(centreX) {
    if (root.cursorX < 0) return 1
    var d = Math.abs(centreX - root.cursorX)
    if (d >= root.magRadius) return 1
    var t = 1 - d / root.magRadius
    // Ease so the falloff is gentle near the cursor and steep further out.
    return 1 + (root.maxScale - 1) * t * t
  }

  // The panel. Translucent rather than blurred — the shell has no blur effect
  // available, and a translucent pill still reads as a dock.
  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: Qt.rgba(0.62, 0.62, 0.66, 0.42)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.25)
  }

  // Catches the cursor so magnification works across the whole dock, including
  // the gaps between icons.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: function(mouse) { root.cursorX = mouse.x }
    onExited: function() { root.cursorX = -1 }
    onContainsMouseChanged: function() { if (!containsMouse) root.cursorX = -1 }
    onClicked: function(mouse) { root.cursorX = mouse.x }
  }

  // The app icons, positioned absolutely so each can scale around its own
  // centre without the row reflowing.
  Repeater {
    model: root.slots
    delegate: Item {
      required property var modelData
      readonly property real centreX: root.padX + modelData.index * (root.iconSize + root.iconGap) + root.iconSize / 2
      readonly property real scale: root.scaleFor(centreX)

      x: centreX - root.iconSize * scale / 2
      // Magnified icons lift, the way the macOS dock raises the hovered item.
      y: root.height / 2 - root.iconSize * scale / 2 - (scale - 1) * root.iconSize * 0.22
      width: root.iconSize * scale
      height: root.iconSize * scale

      Image {
        anchors.fill: parent
        asynchronous: true
        smooth: false
        source: parent.modelData.source
        visible: parent.modelData.source.length > 0
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function() { root.launch(parent.modelData) }
        onEntered: function() {
          if (root.bar && root.bar.showTooltip) root.bar.showTooltip(parent, parent.modelData.name)
        }
      }
    }
  }

  // System control icons at the right end of the dock.
  Item {
    id: sysContainer
    x: root.padX + root.slots.length * (root.iconSize + root.iconGap) - root.iconGap + root.sysPadAfterApps
    y: root.height / 2 - root.sysSize / 2
    width: root.sysControls.length * root.sysSize + (root.sysControls.length - 1) * root.sysGap
    height: root.sysSize

    Repeater {
      model: root.sysControls
      delegate: Rectangle {
        x: index * (root.sysSize + root.sysGap)
        y: 0
        width: root.sysSize
        height: root.sysSize
        radius: 5
        color: Qt.rgba(0.2, 0.6, 1, 0.35)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.4)

        Text {
          anchors.centerIn: parent
          text: {
            var ctrl = root.sysControls[index]
            if (!ctrl) return ""
            var id = ctrl.id
            if (id === "network")   return ""
            if (id === "bluetooth") return ""
            if (id === "audio")     return ""
            if (id === "power")     return ""
            return id.charAt(0).toUpperCase()
          }
          color: "white"
          font.pixelSize: 14
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: function() {
            var ctrl = root.sysControls[index]
            if (ctrl) root.togglePanel(ctrl.cmd)
          }
          onEntered: function() {
            var ctrl = root.sysControls[index]
            if (root.bar && root.bar.showTooltip && ctrl) root.bar.showTooltip(parent, ctrl.id)
          }
        }
      }
    }
  }

}

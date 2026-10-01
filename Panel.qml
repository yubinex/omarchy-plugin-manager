import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Lists installed plugins with a switch each. Flipping switches only stages
// changes; APPLY hands the whole set to bin/plugin-manager in one go.
//
// Adding or removing a bar entry rebuilds every bar widget, this panel
// included, so apply runs detached and reopens the panel when it is done;
// the outcome is read back from last-apply.json.
Panel {
  id: root
  moduleName: "yubinex.plugin-manager"
  manageIpc: false

  property var anchorItem: null
  property string helper: ""
  property var plugins: []
  property bool loading: false
  property string loadError: ""
  // id -> desired enabled state, only for plugins whose switch was flipped.
  property var pending: ({})
  property bool showBuiltIn: false
  property bool applying: false
  property var lastApply: null
  property bool reloadQueued: false
  // The footer names the last apply's changes for 30 seconds after it ran.
  property bool showLastApply: false
  onLastApplyChanged: {
    var age = lastApply ? Date.now() - lastApply.at : Infinity
    showLastApply = age < 30 * 1000
    if (showLastApply) {
      lastApplyExpiry.interval = Math.max(1, 30 * 1000 - age)
      lastApplyExpiry.restart()
    }
  }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy-plugin-manager"
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int pendingCount: Object.keys(pending).length
  // Built-in services (lock screen, polkit, notifications…) are left out on
  // purpose: a casual switch panel should not make those easy to turn off.
  readonly property var visiblePlugins: plugins.filter(function(p) {
    return !p.firstParty || (showBuiltIn && p.barWidget)
  })
  readonly property var barWidgets: visiblePlugins.filter(function(p) { return p.barWidget })
  readonly property var otherPlugins: visiblePlugins.filter(function(p) { return !p.barWidget })
  readonly property int visibleEnabledCount: visiblePlugins.filter(function(p) { return p.enabled }).length

  // Changes can land while a listing is in flight; never drop the newer one.
  function load() {
    if (!helper) return
    if (listProcess.running) {
      reloadQueued = true
      return
    }
    loading = true
    loadError = ""
    listProcess.running = true
  }

  function desired(plugin) {
    return pending[plugin.id] !== undefined ? pending[plugin.id] : plugin.enabled
  }

  function flip(plugin) {
    if (applying) return
    var next = {}
    for (var id in pending) next[id] = pending[id]
    var value = !desired(plugin)
    if (value === plugin.enabled) delete next[plugin.id]
    else next[plugin.id] = value
    pending = next
  }

  function nameOf(id) {
    for (var i = 0; i < plugins.length; ++i) if (plugins[i].id === id) return plugins[i].name
    var parts = String(id).split(".")
    return parts[parts.length - 1]
  }

  function placeText(memory) {
    var text = memory.section
    if (memory.after) text += ", after " + nameOf(memory.after)
    else if (memory.before) text += ", before " + nameOf(memory.before)
    return text
  }

  function hint(plugin) {
    var on = desired(plugin)
    if (!plugin.barWidget) return plugin.kinds.join(", ") + (on ? "" : " · off")
    var memory = plugin.remembered
    var settingsCount = plugin.rememberedSettings ? plugin.rememberedSettings.length : 0
    var settingsText = settingsCount ? " · " + settingsCount + " setting" + (settingsCount === 1 ? "" : "s") : ""
    if (on && plugin.enabled) return "bar · " + plugin.section + settingsText
    if (!on && plugin.enabled) return "will be removed · place" + (settingsCount ? " and settings" : "") + " remembered"
    if (on) return memory ? "returns to " + placeText(memory) + settingsText : "goes to its default spot"
    return memory ? "off · remembers " + placeText(memory) : "off"
  }

  function applyChanges() {
    if (!pendingCount || applying) return
    applying = true
    Quickshell.execDetached(["python3", helper, "apply", JSON.stringify(pending), "--reopen"])
  }

  function resultText() {
    if (applying) return "Applying " + pendingCount + " change" + (pendingCount === 1 ? "" : "s") + "…"
    if (pendingCount) return pendingCount + " change" + (pendingCount === 1 ? "" : "s") + " pending"
    // Name what the last apply did, briefly; afterwards describe the list.
    if (showLastApply) {
      if (lastApply.errors.length) return "Failed: " + lastApply.errors.join("; ")
      var parts = []
      for (var id in lastApply.changes) parts.push(nameOf(id) + (lastApply.changes[id] ? " on" : " off"))
      return "Applied: " + parts.join(", ")
    }
    return visibleEnabledCount + " of " + visiblePlugins.length + " on"
  }

  function readLastApply() {
    try {
      lastApply = JSON.parse(lastApplyFile.text())
    } catch (e) {
      lastApply = null
    }
  }

  onOpenedChanged: {
    if (opened) {
      readLastApply()
      load()
    } else if (!applying) {
      pending = ({})
    }
  }

  Timer {
    id: lastApplyExpiry
    onTriggered: root.showLastApply = false
  }

  Process {
    id: listProcess
    command: ["python3", root.helper, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        root.loading = false
        if (root.reloadQueued) {
          root.reloadQueued = false
          Qt.callLater(root.load)
        }
        try {
          var parsed = JSON.parse(text)
          if (Array.isArray(parsed)) root.plugins = parsed
          else root.loadError = parsed.error || "Unexpected response"
        } catch (e) {
          root.loadError = "Could not list plugins"
        }
      }
    }
    stderr: SplitParser {
      onRead: data => console.warn(root.moduleName + ": " + data)
    }
  }

  // When an apply does not touch the bar layout (services, overlays), this
  // panel survives it; pick the outcome up from the file instead.
  FileView {
    id: lastApplyFile
    path: root.stateDir + "/last-apply.json"
    // Absent until the first apply.
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      root.readLastApply()
      if (root.applying) {
        root.applying = false
        root.pending = ({})
      }
      if (root.opened) root.load()
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool current: false
    property bool active: true
    signal clicked()
    implicitWidth: chipLabel.implicitWidth + Style.space(16)
    implicitHeight: Style.space(25)
    radius: Style.space(3)
    opacity: active ? 1 : 0.35
    color: current ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16) : "transparent"
    border.width: 1
    border.color: current ? root.fg : root.dim
    Text {
      id: chipLabel
      anchors.centerIn: parent
      text: chip.label
      color: chip.current ? root.fg : root.dim
      font.family: root.fontFamily
      font.pixelSize: 11
      font.bold: true
    }
    MouseArea {
      anchors.fill: parent
      enabled: chip.active
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  component PluginRow: Item {
    id: row
    required property var modelData
    readonly property bool on: root.desired(modelData)
    readonly property bool changed: root.pending[modelData.id] !== undefined
    width: parent ? parent.width : 0
    height: Style.space(42)

    Column {
      anchors.left: parent.left
      anchors.right: toggle.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: (row.changed ? "● " : "") + row.modelData.name
        elide: Text.ElideRight
        color: row.on ? root.fg : root.dim
        font.family: root.fontFamily
        font.pixelSize: 14
        font.bold: true
      }
      Text {
        width: parent.width
        text: root.hint(row.modelData)
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 11
      }
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: row.on
      busy: root.applying
      interactive: false
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: root.applying ? Qt.ArrowCursor : Qt.PointingHandCursor
      onClicked: root.flip(row.modelData)
    }
  }

  component SectionLabel: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: 11
    font.bold: true
    topPadding: Style.space(4)
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(content.implicitHeight + footer.implicitHeight + Style.space(10), Style.space(760))
    focusTarget: keyboardCatcher

    PanelKeyCatcher {
      id: keyboardCatcher
      anchors.fill: parent
      z: -1
      onCloseRequested: root.close()
    }

    Flickable {
      id: scroll
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(10)
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: content
        width: scroll.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          Column {
            width: parent.width - builtInChip.width
            spacing: Style.space(2)
            Text {
              text: "PLUGIN MANAGER"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 12
              font.bold: true
            }
            Text {
              width: parent.width
              text: "PLUGINS"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1.0
            }
          }
          Chip {
            id: builtInChip
            anchors.verticalCenter: parent.verticalCenter
            label: "BUILT-IN"
            current: root.showBuiltIn
            onClicked: root.showBuiltIn = !root.showBuiltIn
          }
        }

        PanelSeparator { width: parent.width }

        Text {
          width: parent.width
          visible: root.loading && !root.plugins.length || root.loadError !== ""
          text: root.loadError || "Loading plugins…"
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 13
        }

        SectionLabel {
          visible: root.barWidgets.length > 0
          text: "BAR WIDGETS"
        }
        Column {
          width: parent.width
          Repeater {
            model: root.barWidgets
            delegate: PluginRow {}
          }
        }

        SectionLabel {
          visible: root.otherPlugins.length > 0
          text: "SERVICES, PANELS & OVERLAYS"
        }
        Column {
          width: parent.width
          Repeater {
            model: root.otherPlugins
            delegate: PluginRow {}
          }
        }
      }
    }

    Column {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: Style.space(10)

      PanelSeparator { width: parent.width }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          width: parent.width - revertChip.width - applyChip.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: root.resultText()
          elide: Text.ElideRight
          color: root.lastApply && root.lastApply.errors.length && !root.pendingCount && !root.applying
            ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: 12
        }
        Chip {
          id: revertChip
          label: "REVERT"
          active: root.pendingCount > 0 && !root.applying
          onClicked: root.pending = ({})
        }
        Chip {
          id: applyChip
          label: root.pendingCount ? "APPLY (" + root.pendingCount + ")" : "APPLY"
          current: root.pendingCount > 0
          active: root.pendingCount > 0 && !root.applying
          onClicked: root.applyChanges()
        }
      }
    }
  }
}

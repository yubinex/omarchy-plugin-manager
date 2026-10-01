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
  property int applyingCount: 0
  // The opposite of what the last apply actually changed; UNDO applies it.
  // An undo cannot itself be undone; the switches do that job.
  readonly property var undoChanges: {
    var changes = {}
    if (!lastApply || !lastApply.done || lastApply.undo) return changes
    for (var i = 0; i < lastApply.done.length; ++i) {
      var id = lastApply.done[i]
      if (lastApply.changes[id] !== undefined) changes[id] = !lastApply.changes[id]
    }
    return changes
  }
  readonly property bool canUndo: Object.keys(undoChanges).length > 0

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy-plugin-manager"
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int pendingCount: Object.keys(pending).length
  // Below this the footer status gets its own line above the buttons.
  readonly property bool narrowLayout: popup.contentWidth < Style.space(380)
  // Built-in services (lock screen, polkit, notifications…) are left out on
  // purpose: a casual switch panel should not make those easy to turn off.
  readonly property var visiblePlugins: plugins.filter(function(p) {
    return !p.firstParty || (showBuiltIn && p.barWidget)
  })
  // Built-ins get their own section and a badge, so switching one is never
  // mistaken for switching a plugin you installed.
  readonly property var barWidgets: visiblePlugins.filter(function(p) { return p.barWidget && !p.firstParty })
  readonly property var otherPlugins: visiblePlugins.filter(function(p) { return !p.barWidget })
  readonly property var builtInWidgets: visiblePlugins.filter(function(p) { return p.firstParty })
  readonly property int pendingBuiltInCount: plugins.filter(function(p) {
    return p.firstParty && pending[p.id] !== undefined
  }).length
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

  function run(changes, undo) {
    var count = Object.keys(changes).length
    if (!count || applying) return
    applying = true
    applyingCount = count
    var args = ["python3", helper, "apply", JSON.stringify(changes), "--reopen"]
    if (undo) args.push("--undo")
    Quickshell.execDetached(args)
  }

  function applyChanges() { run(pending, false) }
  function undoLastApply() { run(undoChanges, true) }

  function plural(count) { return count + " change" + (count === 1 ? "" : "s") }

  // While nothing is staged the footer describes the last apply, which is
  // what UNDO acts on.
  function resultText() {
    if (applying) return "Applying " + plural(applyingCount) + "…"
    if (pendingCount) return plural(pendingCount) + " pending"
      + (pendingBuiltInCount ? " · " + pendingBuiltInCount + " built-in" : "")
    if (lastApply) {
      if (lastApply.errors.length) return "Failed: " + lastApply.errors.join("; ")
      var parts = []
      var state = lastApply.undo ? [" back on", " back off"] : [" on", " off"]
      for (var id in lastApply.changes) parts.push(nameOf(id) + (lastApply.changes[id] ? state[0] : state[1]))
      if (parts.length) return (lastApply.undo ? "Undone · " : "Last: ") + parts.join(", ")
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

      Row {
        width: parent.width
        spacing: Style.space(6)
        Text {
          width: Math.min(implicitWidth, parent.width - (builtInBadge.visible ? builtInBadge.width + parent.spacing : 0))
          anchors.verticalCenter: parent.verticalCenter
          text: (row.changed ? "● " : "") + row.modelData.name
          elide: Text.ElideRight
          color: row.on ? root.fg : root.dim
          font.family: root.fontFamily
          font.pixelSize: 14
          font.bold: true
        }
        Rectangle {
          id: builtInBadge
          visible: row.modelData.firstParty
          anchors.verticalCenter: parent.verticalCenter
          width: badgeLabel.implicitWidth + Style.space(8)
          height: badgeLabel.implicitHeight + Style.space(2)
          radius: Style.space(2)
          color: "transparent"
          border.width: 1
          border.color: Color.accent
          Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: "BUILT-IN"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }
        }
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

  component StatusText: Text {
    text: root.resultText()
    color: root.lastApply && root.lastApply.errors.length && !root.pendingCount && !root.applying
      ? Color.urgent : root.dim
    font.family: root.fontFamily
    font.pixelSize: 12
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
      // Leave a gutter for the scroll indicator when the list overflows.
      anchors.rightMargin: interactive ? Style.space(10) : 0
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

        SectionLabel {
          visible: root.builtInWidgets.length > 0
          text: "BUILT-IN BAR WIDGETS"
        }
        Text {
          width: parent.width
          visible: root.builtInWidgets.length > 0
          text: "Part of Omarchy. Switching one off only removes it from the bar; the panel brings it back with its settings."
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 11
        }
        Column {
          width: parent.width
          Repeater {
            model: root.builtInWidgets
            delegate: PluginRow {}
          }
        }
      }
    }

    Rectangle {
      visible: scroll.interactive
      anchors.right: parent.right
      width: Style.space(3)
      radius: width / 2
      y: scroll.y + scroll.height * scroll.visibleArea.yPosition
      height: scroll.height * scroll.visibleArea.heightRatio
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
    }

    Column {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: Style.space(10)

      PanelSeparator { width: parent.width }

      StatusText {
        visible: root.narrowLayout
        width: parent.width
        wrapMode: Text.WordWrap
      }

      Row {
        anchors.right: parent.right
        spacing: Style.space(8)
        StatusText {
          visible: !root.narrowLayout
          width: visible ? footer.width - revertChip.width - applyChip.width - parent.spacing * 2 : 0
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
        }
        // Discards staged switches; with nothing staged it undoes the last
        // apply instead.
        Chip {
          id: revertChip
          label: root.pendingCount || !root.canUndo ? "REVERT" : "UNDO"
          active: !root.applying && (root.pendingCount > 0 || root.canUndo)
          onClicked: {
            if (root.pendingCount) root.pending = ({})
            else root.undoLastApply()
          }
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

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A puzzle-piece button that opens the plugin panel. It also keeps the
// remembered bar positions current: whenever shell.json changes, one
// instance records where every bar widget sits, so a widget disabled by any
// means (this panel, the CLI, a manual edit) can later come back in place.
BarWidget {
  id: root
  moduleName: "yubinex.plugin-manager"

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string helper: pluginDir + "/bin/plugin-manager"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

  // A bar surface exists per monitor; only the first copy needs to record.
  readonly property bool recorder: {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    return items.length === 0 || items[0] === root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function snapshot() {
    if (recorder && !snapshotProcess.running) snapshotProcess.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.helper = helper
    panelLoader.item.settings = settings
    panelLoader.item.anchorItem = button
    panelLoader.item.bar = bar
  }

  onSettingsChanged: injectPanel()
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }

  Component.onCompleted: snapshotDebounce.restart()

  FileView {
    path: root.configPath
    watchChanges: true
    onFileChanged: snapshotDebounce.restart()
  }

  // A drag or a multi-plugin apply writes shell.json several times in a row.
  Timer {
    id: snapshotDebounce
    interval: 1500
    onTriggered: {
      root.snapshot()
      // Keep an open panel in step with changes made elsewhere.
      if (root.opened && panelLoader.item) panelLoader.item.load()
    }
  }

  Process {
    id: snapshotProcess
    command: ["python3", root.helper, "snapshot"]
    stderr: SplitParser {
      onRead: data => console.warn(root.moduleName + ": " + data)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F0431}"
    fontSize: Style.bar.iconFont
    tooltipText: "Plugin Manager"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Plugin Manager"
  }
}

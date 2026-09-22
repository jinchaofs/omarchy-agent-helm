import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Agent Helm — one popup for the whole agent lifecycle:
//   click a row      → open that agent (default stays untouched)
//   click the dot    → make it the default (notification confirms)
//   Install button   → omarchy-default-agent's install flow for missing ones
//
// State comes from bin/agent-status (labels/icons copied from the stock
// menu table, local-only install detection); actions delegate to
// bin/agent-open, bin/agent-set, and omarchy-default-agent so no
// per-agent flag table is duplicated here.
Panel {
  id: root
  moduleName: "jinchaofs.agent-switcher"
  ipcTarget: "jinchaofs.agent-switcher"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string defaultAgent: ""
  property var rows: []
  readonly property var installedRows: rows.filter(function(r) { return r.installed })
  readonly property var missingRows: rows.filter(function(r) { return !r.installed })
  readonly property int rowCount: installedRows.length + missingRows.length
  property int cursor: 0

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function scriptPath(name) {
    return Qt.resolvedUrl("bin/" + name).toString().replace("file://", "")
  }

  // bar.run takes one shell string, so arguments need quoting; menu labels
  // are stock strings and never carry quotes themselves.
  function shq(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function allRows() {
    return installedRows.concat(missingRows)
  }

  function rowAt(index) {
    var all = allRows()
    if (all.length === 0) return null
    return all[Math.max(0, Math.min(index, all.length - 1))]
  }

  function defaultRow() {
    for (var i = 0; i < installedRows.length; i++)
      if (installedRows[i].id === defaultAgent) return installedRows[i]
    return installedRows.length > 0 ? installedRows[0] : null
  }

  function refresh() {
    // Restart unconditionally: a detector that stalls (bad PATH, a slow
    // --check) would otherwise leave running=true forever and every reopen
    // would skip the rerun — the panel stuck on "Detecting agents…".
    if (statusProc.running) statusProc.running = false
    statusProc.running = true
  }

  // Enter / row click: installed → launch, missing → install flow.
  function activateRow(row) {
    if (!row) return
    root.close()
    if (row.installed) root.bar.run(root.scriptPath("agent-open") + " " + row.id)
    else root.bar.run("omarchy-default-agent " + row.id)
  }

  // The dot / right arrow: move the default, launch nothing.
  function setDefault(row) {
    if (!row || !row.installed || row.id === root.defaultAgent) return
    root.bar.run(root.scriptPath("agent-set") + " " + row.id + " " + root.shq(row.label))
    root.defaultAgent = row.id
  }

  // Delegates register themselves here: Repeater exposes no objectAt() in
  // this Qt build, and keyed lookup stays correct when a row's index shifts
  // between the installed and missing sections.
  property var rowRegistry: ({})

  function registerRow(agentId, obj) {
    if (!agentId) return
    var next = Object.assign({}, rowRegistry)
    next[agentId] = obj
    rowRegistry = next
  }

  function unregisterRow(agentId, obj) {
    if (!agentId || rowRegistry[agentId] !== obj) return
    var next = Object.assign({}, rowRegistry)
    delete next[agentId]
    rowRegistry = next
  }

  // Scroll the cursor's row into view; the row maps its own geometry into
  // flickable content space and nudges contentY only far enough to reveal it.
  function ensureCursorVisible() {
    if (rowCount === 0 || !panelFlick) return
    var row = rowAt(cursor)
    if (!row) return
    var obj = rowRegistry[row.id]
    if (obj) obj.ensureVisible()
  }

  onOpenedChanged: if (opened) {
    cursor = 0
    var all = allRows()
    for (var i = 0; i < all.length; i++)
      if (all[i].id === defaultAgent) { cursor = i; break }
    refresh()
  }

  Process {
    id: statusProc
    command: [root.scriptPath("agent-status")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || ""))
          root.defaultAgent = data.default || ""
          root.rows = data.agents || []
          // Rows land after status arrives; bring the cursor's row into view
          // once they exist.
          Qt.callLater(root.ensureCursorVisible)
        } catch (e) {
          // keep the last known state on a malformed read
        }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    // WidgetButton shows this on hover via bar.showTooltip().
    tooltipText: "Agent Helm"
    onPressed: function(buttonCode) {
      // Right button skips the panel: straight to the current default.
      if (buttonCode === Qt.RightButton) root.activateRow(root.defaultRow())
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        // Horizontal = set default (a radio list has no sideways to walk);
        // vertical walks the combined installed-then-missing list with wrap.
        if (dx > 0) root.setDefault(root.rowAt(root.cursor))
        if (dy !== 0 && root.rowCount > 0) {
          root.cursor = (root.cursor + dy + root.rowCount) % root.rowCount
          Qt.callLater(root.ensureCursorVisible)
        }
      }
      onActivateRequested: root.activateRow(root.rowAt(root.cursor))
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "d" || t === "D") root.setDefault(root.rowAt(root.cursor))
      }

      // The list scrolls: 14 rows outgrow the panel on short screens, and a
      // clipped list hides the very agents it exists to surface.
      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelSectionHeader {
            visible: root.installedRows.length > 0
            width: parent.width
            text: "INSTALLED"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            id: installedRep
            model: root.installedRows
            AgentRow {
              required property var modelData
              required property int index
              width: column.width
              agent: modelData
              // Cursor walks one combined list; this section owns the head of it.
              cursorHere: root.cursor === index
              isDefault: modelData.id === root.defaultAgent
              onRowClicked: root.activateRow(modelData)
              onDotClicked: root.setDefault(modelData)
            }
          }

          PanelSectionHeader {
            visible: root.missingRows.length > 0
            width: parent.width
            text: "NOT INSTALLED"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            id: missingRep
            model: root.missingRows
            AgentRow {
              required property var modelData
              required property int index
              width: column.width
              agent: modelData
              cursorHere: root.cursor === root.installedRows.length + index
              isDefault: false
              onRowClicked: root.activateRow(modelData)
              onDotClicked: root.setDefault(modelData)
            }
          }

          Text {
            visible: root.rowCount === 0
            width: parent.width
            topPadding: Style.space(16)
            text: statusProc.running ? "Detecting agents…" : "No agents found."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            topPadding: Style.space(6)
            text: "Enter open · → or d set default · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  // One list row: dot · icon · label · trailing action.
  //   installed: filled dot when default, click the rest to open
  //   missing:   dot disabled, trailing Install button
  component AgentRow: Item {
    id: row
    property var agent: null
    property bool cursorHere: false
    property bool isDefault: false
    property bool hovered: hover.containsMouse

    signal rowClicked()
    signal dotClicked()

    implicitHeight: Style.space(48)

    Component.onCompleted: root.registerRow(row.agent ? row.agent.id : "", row)
    Component.onDestruction: root.unregisterRow(row.agent ? row.agent.id : "", row)

    // Reveal this row in the panel's Flickable: only nudge contentY when
    // the row actually falls outside the viewport.
    function ensureVisible() {
      if (!panelFlick) return
      var top = mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var max = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop) panelFlick.contentY = Math.max(0, Math.min(top, max))
      else if (bottom > viewBottom) panelFlick.contentY = Math.max(0, Math.min(bottom - panelFlick.height, max))
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: row.cursorHere || row.hovered
        ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
        : "transparent"

      Behavior on color {
        ColorAnimation { duration: 120 }
      }
    }

    // Whole-row target: open (installed) or install (missing). Sits below the
    // dot and the button so their clicks win where they overlap.
    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      onClicked: row.rowClicked()
    }

    // Radio dot — the set-default control.
    Rectangle {
      id: dot
      width: Style.space(16)
      height: Style.space(16)
      radius: width / 2
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      color: "transparent"
      // Classic radio look: every row keeps its ring; the default adds the
      // filled center in the accent color.
      border.width: Style.space(2)
      border.color: row.isDefault ? root.accent : root.dim
      opacity: row.agent && row.agent.installed ? 1 : 0.35

      Rectangle {
        visible: row.isDefault
        anchors.centerIn: parent
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        color: root.accent
      }

      // Ring color transitions smoothly when the default moves.
      Behavior on border.color {
        ColorAnimation { duration: 120 }
      }

      // Generous click target around the small dot.
      MouseArea {
        id: dotHover
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        enabled: row.agent && row.agent.installed
        hoverEnabled: true
        onClicked: row.dotClicked()
      }

      PanelToolTip {
        visible: dotHover.containsMouse
        text: row.isDefault
          ? row.agent.label + " is the default agent"
          : "Set " + (row.agent ? row.agent.label : "") + " as default"
        fontFamily: root.fontFamily
      }
    }

    Text {
      id: icon
      width: Style.space(24)
      anchors.left: dot.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      text: row.agent ? row.agent.icon : ""
      visible: text !== ""
      color: row.agent && row.agent.installed ? root.foreground : root.dim
      font.family: row.agent && row.agent.iconFont === "omarchy" ? "omarchy" : root.fontFamily
      font.pixelSize: Style.font.heading
    }

    Text {
      id: label
      text: row.agent ? row.agent.label : ""
      color: row.agent && row.agent.installed ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      // The default row is the one the panel opens on; weight says so before
      // the eye reaches the dot.
      font.bold: row.isDefault
      elide: Text.ElideRight
      anchors.left: icon.visible ? icon.right : dot.right
      anchors.leftMargin: icon.visible ? Style.space(6) : Style.space(12)
      anchors.right: action.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    // Trailing action: "default" hint on the current default, Install on a
    // missing agent, nothing on an ordinary installed row.
    Item {
      id: action
      width: actionLabel.implicitWidth + Style.space(24)
      height: Style.space(28)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      readonly property bool showInstall: row.agent && !row.agent.installed
      readonly property bool showDefaultTag: row.isDefault

      visible: showInstall || showDefaultTag

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        visible: action.showInstall
        color: installHover.containsMouse
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)
          : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
        border.width: 1
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
      }

      Text {
        id: actionLabel
        anchors.centerIn: parent
        text: action.showInstall ? "Install" : "default"
        color: action.showInstall ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: action.showInstall
      }

      MouseArea {
        id: installHover
        anchors.fill: parent
        hoverEnabled: true
        visible: action.showInstall
        onClicked: row.rowClicked()
      }
    }
  }
}

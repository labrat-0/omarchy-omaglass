import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.labrat-0.omaglass"
  ipcTarget: "io.github.labrat-0.omaglass"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ─────────────────────────────────────────────────────────── settings

  readonly property string airplayName: String(setting("airplayName", "Omarchy"))
  readonly property string airplayPin: String(setting("airplayPin", ""))
  readonly property int refreshIntervalSec: Math.max(3, Number(setting("refreshIntervalSec", 8)))

  // Android rotates its wireless-debugging port on every toggle and reboot, so
  // mDNS is the source of truth. These survive only for a device reachable but
  // not advertising, e.g. one put on a fixed port with `adb tcpip`.
  // The debug-free path: an app on the phone (ScreenStream and similar) uses
  // MediaProjection to serve its screen over the LAN, so nothing has to be
  // enabled in developer options. View only, and the phone's lock screen
  // renders black — an OS restriction on MediaProjection, not a bug here.
  readonly property string configuredStreamUrl: String(setting("streamUrl", ""))
  readonly property string streamPort: String(setting("streamPort", "8080"))

  // Found by scanning rather than typed. The phone knows its own address and
  // the app prints it, but making a person carry it across to the laptop is
  // the whole friction — so look for it instead of asking.
  property string foundStreamUrl: ""
  property bool scanning: false

  readonly property string streamUrl: foundStreamUrl !== "" ? foundStreamUrl : configuredStreamUrl
  readonly property bool haveStream: streamUrl !== ""
  property bool streamReachable: false
  property bool streamPlaying: false

  // Play Store listing for the streaming app. Unlike the adb pairing payload,
  // this is only a URL, so the phone's ordinary camera is the right thing to
  // scan it with.
  readonly property string installUrl:
    "https://play.google.com/store/apps/details?id=info.dvkr.screenstream"
  property bool showInstall: false
  property var qrRows: []
  property int qrSize: 0

  readonly property string deviceIp: String(setting("deviceIp", ""))
  readonly property string devicePort: String(setting("devicePort", ""))
  readonly property string manualTarget:
    deviceIp !== "" && devicePort !== "" ? deviceIp + ":" + devicePort : ""

  // ────────────────────────────────────────────────────────────── state

  property string discoveredTarget: ""
  property string discoveredName: ""
  property bool androidConnected: false
  property bool androidMirroring: false

  // "off" | "running" (waiting for a phone) | "streaming"
  property string receiverState: "off"

  property string actionStatus: ""
  property int cursorColumn: 0   // 0 = Android, 1 = Apple
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property string androidTarget: discoveredTarget !== "" ? discoveredTarget : manualTarget
  readonly property bool haveAndroid: androidTarget !== ""
  readonly property string androidLabel: discoveredName !== "" ? discoveredName : androidTarget
  // Only meaningful for an HTTP address; an rtsp:// one is never probed, so
  // it must not be reported as offline on the strength of a probe never run.
  readonly property bool streamOffline:
    haveStream && streamUrl.indexOf("http") === 0 && !streamReachable
  readonly property bool receiverRunning: receiverState !== "off"
  readonly property bool receiverStreaming: receiverState === "streaming"
  readonly property bool anyMirroring: androidMirroring || receiverStreaming || streamPlaying

  // ───────────────────────────────────────────────────────────── theming

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color barIconColor: anyMirroring
    ? Color.accent
    : ((androidConnected || receiverRunning) ? barForeground : Qt.darker(barForeground, 1.55))

  readonly property string statusText: {
    if (androidMirroring && receiverStreaming) return "Mirroring " + androidLabel + " and iPhone"
    if (androidMirroring) return "Mirroring " + androidLabel
    if (receiverStreaming) return "Mirroring iPhone"
    if (streamPlaying) return "Streaming Android \u00b7 view only"
    if (receiverRunning && androidConnected) return androidLabel + " ready · receiver waiting"
    if (receiverRunning) return "Receiver waiting for an iPhone"
    if (androidConnected) return "Connected · " + androidLabel
    if (haveAndroid) return "Found " + androidLabel
    if (haveStream) return streamReachable ? "Stream ready" : "Stream offline"
    return "No device"
  }

  // ───────────────────────────────────────────────────────────── actions

  // Two platforms, deliberately not presented as one list: Android is a device
  // you reach out to, iPhone is a receiver that waits to be reached. Flattened
  // into a single array only so one cursor can walk both sections.
  // Short labels; the detail lives in the hover tooltip so two columns stay
  // scannable rather than turning into paragraphs.
  readonly property var androidActions: {
    var out = []
    if (androidMirroring) {
      out.push({ key: "a-stop", glyph: "󰓛", title: "Stop",
                 tip: "Close every scrcpy window" })
    } else if (androidConnected) {
      out.push({ key: "a-mirror", glyph: "󰍹", title: "Mirror",
                 tip: "Normal resizable window, with touch and keyboard control" })
      out.push({ key: "a-float", glyph: "󰉪", title: "Floating",
                 tip: "Small window kept above everything else" })
      out.push({ key: "a-screenoff", glyph: "󰶐", title: "Screen off",
                 tip: "Mirror while the phone's own display sleeps" })
    } else if (haveAndroid) {
      out.push({ key: "a-connect", glyph: "󰐗", title: "Connect",
                 tip: "adb connect " + androidTarget })
    }
    if (androidConnected) {
      out.push({ key: "a-disconnect", glyph: "󰅖", title: "Disconnect",
                 tip: "Drops adb — ends mirroring and control access" })
    }
    if (!haveStream) {
      out.push({ key: "a-install", glyph: "󰐎",
                 title: showInstall ? "Hide QR" : "Get the app",
                 tip: "Shows a QR for the Play Store listing. Scan it with the "
                      + "phone's normal camera — it is only a link." })
      out.push({ key: "a-find", glyph: "󰍉",
                 title: scanning ? "Searching…" : "Find phone",
                 tip: "Scans this network for a phone running a screen-sharing "
                      + "app. No developer options needed — install the app, "
                      + "start it, then press this." })
    }
    // Offered whenever a window exists, not only when the phone is still
    // sending: stopping from the phone leaves mpv holding a dead stream, and
    // without this there is no way out of that from the menu.
    if (streamPlaying) {
      out.push({ key: "a-streamstop", glyph: "󰓛", title: "Stop stream",
                 tip: "Close the streaming window" })
    }
    if (haveStream && !streamPlaying) {
      out.push({ key: "a-stream", glyph: "󰖟",
                 title: streamOffline ? "Stream (offline)" : "Stream",
                 tip: streamOffline
                   ? "The phone is no longer serving " + streamUrl
                     + ". Start the app again, or Reset to search."
                   : "No developer options needed. View only, and the lock "
                     + "screen stays black." })
    }
    // A found address outlives the stream that produced it, so there has to
    // be a way to forget it and look again.
    if (haveStream) {
      out.push({ key: "a-streamreset", glyph: "󰑐", title: "Reset stream",
                 tip: "Forget this address and search the network again" })
    }
    return out
  }

  readonly property var appleActions: {
    var out = []
    if (receiverRunning) {
      out.push({ key: "r-stop", glyph: "󰓛", title: "Stop",
                 tip: receiverStreaming ? "Ends the current mirror"
                                        : "Stop waiting for a device" })
    } else {
      out.push({ key: "r-start", glyph: "󰐊", title: "Receiver",
                 tip: "Start the AirPlay receiver, then pick \u201C" + airplayName
                      + "\u201D in Control Centre" })
    }
    return out
  }

  readonly property var activeActions: cursorColumn === 0 ? androidActions : appleActions

  // ─────────────────────────────────────────────────────────── behaviour

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function runDetached(command) {
    Quickshell.execDetached(["bash", "-lc", command])
  }

  function refresh() {
    if (!discoverProc.running) discoverProc.running = true
    if (!statusProc.running) statusProc.running = true
    if (!mirrorProc.running) mirrorProc.running = true
    if (!receiverProc.running) receiverProc.running = true
    if (!streamPlayProc.running) streamPlayProc.running = true
    if (haveStream && streamUrl.indexOf("http") === 0 && !streamProbe.running) {
      streamProbe.command = ["bash", "-lc",
        "curl -s -o /dev/null --max-time 2 " + shellQuote(streamUrl) + " && echo up || echo down"]
      streamProbe.running = true
    }
  }

  function connectDevice() {
    if (!haveAndroid) {
      actionStatus = "Nothing advertising — turn on Wireless debugging."
      refresh()
      return
    }
    actionStatus = "Connecting to " + androidTarget + "…"
    connectProc.command = ["bash", "-lc", "adb connect " + shellQuote(androidTarget)]
    connectProc.running = true
  }

  function disconnectDevice() {
    actionStatus = "Disconnecting…"
    runDetached("adb disconnect " + shellQuote(androidTarget))
    statusDelay.restart()
  }

  function startMirror(mode) {
    if (!haveAndroid) {
      actionStatus = "Nothing advertising — turn on Wireless debugging."
      refresh()
      return
    }
    var flags = "--window-title=" + shellQuote(androidLabel + " — " + androidTarget)
    if (mode === "float") flags += " --always-on-top --window-width=420"
    else if (mode === "screenoff") flags += " --turn-screen-off --stay-awake"

    actionStatus = "Starting scrcpy…"
    runDetached("adb connect " + shellQuote(androidTarget) + " >/dev/null 2>&1; "
                + "exec scrcpy -s " + shellQuote(androidTarget) + " " + flags)
    statusDelay.restart()
    close()
  }

  // --profile=low-latency keeps a live screen close to real time; mpv would
  // otherwise buffer it like a video file and run seconds behind.
  function openStream() {
    if (!haveStream) return
    actionStatus = "Opening stream…"
    runDetached("exec mpv --profile=low-latency --no-terminal"
                + " --title=" + shellQuote("OmaGlass — Android (no debugging)")
                + " " + shellQuote(streamUrl))
    close()
  }

  // A whole /24 takes about two seconds at this concurrency, which is fast
  // enough to be a button rather than a background task. Candidates are
  // accepted only if the endpoint answers with an MJPEG content type, so a
  // router admin page on the same port cannot masquerade as a phone.
  function findPhone() {
    if (scanning) return
    scanning = true
    actionStatus = "Looking for a phone on this network…"
    scanProc.command = ["bash", "-lc",
      "SUB=$(ip route | awk '/default/{print $3}' | sed 's|\\.[0-9]*$|.|'); "
      + "[ -n \"$SUB\" ] || exit 0; "
      + "seq 1 254 | sed \"s|^|$SUB|\" | xargs -P 128 -I{} sh -c '"
      + "ct=$(curl -s -o /dev/null -w \"%{content_type}\" --connect-timeout 1 --max-time 2 "
      + "\"http://{}:" + streamPort + "/stream.mjpeg\" 2>/dev/null); "
      + "case \"$ct\" in multipart/*) echo \"http://{}:" + streamPort + "/stream.mjpeg\";; esac"
      + "' 2>/dev/null | head -1"]
    scanProc.running = true
  }

  function toggleInstall() {
    showInstall = !showInstall
    if (showInstall && qrSize === 0) qrProc.running = true
  }

  function resetStream() {
    foundStreamUrl = ""
    streamReachable = false
    actionStatus = "Address cleared — searching again…"
    findPhone()
  }

  function stopStream() {
    actionStatus = "Closing stream…"
    runDetached("for p in $(pgrep -x mpv); do "
                + "grep -qa profile=low-latency /proc/$p/cmdline 2>/dev/null "
                + "&& kill \"$p\"; done")
    statusDelay.restart()
  }

  function stopMirror() {
    actionStatus = "Stopping scrcpy…"
    runDetached("pkill -x scrcpy")
    statusDelay.restart()
  }

  // waylandsink and avdec are pinned rather than left to uxplay's defaults:
  // autovideosink + decodebin resolve to something that never produces a
  // window under Hyprland, and it fails silently — a phone that connects to
  // nothing. -p pins the ports so a firewall rule can exist at all.
  function startReceiver() {
    var cmd = "uxplay -n " + shellQuote(airplayName) + " -vs waylandsink -avdec -p"
    if (airplayPin !== "") cmd += " -pin " + shellQuote(airplayPin)
    actionStatus = "Starting receiver…"
    // The log goes under XDG_RUNTIME_DIR, not /tmp: a fixed path in a
    // world-writable directory can be pre-created as a symlink by another
    // local user, and the redirect would then truncate whatever it points at.
    var logDir = "\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omaglass\""
    runDetached("d=" + logDir + "; mkdir -p -m 700 \"$d\" || exit 1; "
                + "pkill -x uxplay >/dev/null 2>&1; "
                + "exec " + cmd + " >\"$d/uxplay.log\" 2>&1")
    statusDelay.restart()
  }

  function stopReceiver() {
    actionStatus = "Stopping receiver…"
    runDetached("pkill -x uxplay")
    statusDelay.restart()
  }

  function activate(key) {
    if (key === "a-mirror") startMirror("window")
    else if (key === "a-float") startMirror("float")
    else if (key === "a-screenoff") startMirror("screenoff")
    else if (key === "a-stop") stopMirror()
    else if (key === "a-connect") connectDevice()
    else if (key === "a-disconnect") disconnectDevice()
    else if (key === "a-stream") openStream()
    else if (key === "a-find") findPhone()
    else if (key === "a-streamstop") stopStream()
    else if (key === "a-streamreset") resetStream()
    else if (key === "a-install") toggleInstall()
    else if (key === "r-start") startReceiver()
    else if (key === "r-stop") stopReceiver()
  }

  function ensureCursor() {
    var n = activeActions.length
    if (cursorIndex >= n) cursorIndex = Math.max(0, n - 1)
    if (cursorIndex < 0) cursorIndex = 0
  }

  // Left/right crosses between the two platform columns, up/down walks one.
  function moveCursor(dx, dy) {
    cursorActive = true
    if (dx !== 0) {
      cursorColumn = dx > 0 ? 1 : 0
      ensureCursor()
      return
    }
    if (dy === 0) return
    cursorIndex = Math.max(0, Math.min(activeActions.length - 1,
                                       cursorIndex + (dy > 0 ? 1 : -1)))
  }

  function activateCursor() {
    ensureCursor()
    var action = activeActions[cursorIndex]
    if (action) activate(action.key)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    actionStatus = ""
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onActiveActionsChanged: ensureCursor()

  // ────────────────────────────────────────────────────────────── probes

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function mirror(): string { root.startMirror("window"); return "ok" }
    function stop(): string { root.stopMirror(); return "ok" }
    function receiver(on: string): string {
      if (on === "off") root.stopReceiver(); else root.startReceiver()
      return "ok"
    }
    function install(): string { root.toggleInstall(); return root.showInstall ? "shown" : "hidden" }
    function status(): string { return root.statusText }
  }

  // Arch builds android-tools without adb's mDNS backend, so avahi browses and
  // hands adb a plain host:port. Fields are cut in the shell because the QML
  // quoting for an equivalent awk program is unreadable.
  Process {
    id: discoverProc
    command: ["bash", "-lc",
      "timeout 5 avahi-browse -tpr _adb-tls-connect._tcp 2>/dev/null"
      + " | grep '^=;.*;IPv4;' | head -1 | cut -d';' -f8-"]
    stdout: StdioCollector { id: discoverOut; waitForEnd: true }
    onExited: function(exitCode) {
      var line = String(discoverOut.text || "").trim()
      if (line === "") {
        root.discoveredTarget = ""
        root.discoveredName = ""
        return
      }
      var f = line.split(";")
      var ip = f.length > 0 ? f[0] : ""
      var port = f.length > 1 ? f[1] : ""
      var m = f.slice(2).join(";").match(/name=([^"]*)/)
      root.discoveredTarget = (ip !== "" && port !== "") ? ip + ":" + port : ""
      root.discoveredName = m ? m[1] : ""
    }
  }

  Process {
    id: statusProc
    command: ["bash", "-lc", "adb devices 2>/dev/null | awk '$2==\"device\"{print $1}'"]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      var lines = String(statusOut.text || "").trim().split("\n")
        .filter(function(l) { return l.trim() !== "" })
      root.androidConnected = lines.length > 0
    }
  }

  Process {
    id: mirrorProc
    command: ["bash", "-lc", "pgrep -x scrcpy >/dev/null"]
    onExited: function(exitCode) { root.androidMirroring = exitCode === 0 }
  }

  // uxplay only maps a window once a phone is actually streaming, so the
  // window is what separates "waiting" from "mirroring".
  Process {
    id: receiverProc
    command: ["bash", "-lc",
      "pgrep -x uxplay >/dev/null && {"
      + " hyprctl clients -j 2>/dev/null | grep -q '\"class\": \"uxplay\"'"
      + " && echo streaming || echo running; } || echo off"]
    stdout: StdioCollector { id: receiverOut; waitForEnd: true }
    onExited: function(exitCode) {
      var s = String(receiverOut.text || "").trim()
      root.receiverState = (s === "streaming" || s === "running") ? s : "off"
    }
  }

  // Only HTTP streams can be cheaply probed; an RTSP URL is left to mpv to
  // resolve, so it is offered without a liveness claim rather than wrongly
  // reported as down.
  Process {
    id: streamProbe
    command: ["bash", "-lc", "echo down"]
    stdout: StdioCollector { id: streamOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.streamReachable = String(streamOut.text || "").trim() === "up"
    }
  }

  // Identified by the profile flag so an unrelated mpv playing a film is not
  // mistaken for the phone.
  Process {
    id: qrProc
    command: ["bash", "-lc",
      "qrencode --type ASCII --margin 2 --output - " + root.shellQuote(root.installUrl)]
    stdout: StdioCollector { id: qrOut; waitForEnd: true }
    onExited: function(exitCode) {
      // Keep whitespace-only lines: with --margin they are the quiet zone,
      // and dropping them makes the matrix non-square so nothing renders.
      // Only the trailing newline's empty string is discarded.
      var lines = String(qrOut.text || "").split("\n")
      while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
      var rows = []
      for (var i = 0; i < lines.length; i++) {
        var row = ""
        for (var c = 0; c < lines[i].length; c += 2)
          row += lines[i].substr(c, 2).indexOf("#") !== -1 ? "1" : "0"
        rows.push(row)
      }
      // A non-square matrix means the output was truncated; render nothing
      // rather than a code that cannot scan.
      if (rows.length === 0 || rows[0].length !== rows.length) {
        root.qrRows = []; root.qrSize = 0; return
      }
      root.qrRows = rows
      root.qrSize = rows.length
    }
  }

  Process {
    id: streamPlayProc
    command: ["bash", "-lc",
      "for p in $(pgrep -x mpv); do "
      + "grep -qa profile=low-latency /proc/$p/cmdline 2>/dev/null && exit 0; "
      + "done; exit 1"]
    onExited: function(exitCode) { root.streamPlaying = exitCode === 0 }
  }

  Process {
    id: scanProc
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.scanning = false
      var url = String(scanOut.text || "").trim().split("\n")[0]
      if (url !== "") {
        root.foundStreamUrl = url
        root.streamReachable = true
        root.actionStatus = "Found " + url.replace("http://", "").replace("/stream.mjpeg", "")
      } else {
        root.actionStatus = "No phone found. Start the streaming app, then try again."
      }
    }
  }

  Process {
    id: connectProc
    stdout: StdioCollector { id: connectOut; waitForEnd: true }
    stderr: StdioCollector { id: connectErr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(connectOut.text || "").trim() + String(connectErr.text || "").trim()
      if (out.indexOf("connected to") !== -1) root.actionStatus = "Connected"
      else if (out !== "") root.actionStatus = out.split("\n")[0]
      else root.actionStatus = exitCode === 0 ? "Connected" : "Connection failed"
      root.refresh()
    }
  }

  Timer {
    id: statusDelay
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ────────────────────────────────────────────────────────────────── UI

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    iconComponent: Component {
      Item {
        OmaGlassIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.barIconColor
        }
      }
    }
    tooltipText: root.statusText
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "m" || t === "M") root.startMirror("window")
        else if (t === "f" || t === "F") root.startMirror("float")
        else if (t === "s" || t === "S") root.stopMirror()
        else if (t === "r" || t === "R") root.receiverRunning ? root.stopReceiver() : root.startReceiver()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Column {
          width: parent.width
          spacing: Style.space(2)

          OmaGlassIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            iconSize: Style.space(34)
            color: root.anyMirroring ? Color.accent : root.foreground
          }

          Item { width: 1; height: Style.space(6) }

          Text {
            width: parent.width
            text: "OmaGlass"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: parent.width
            text: root.statusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Item {
            width: parent.width
            height: liveTag.visible ? liveTag.implicitHeight + Style.space(6) : 0

            BorderSurface {
              id: liveTag
              visible: root.anyMirroring
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              implicitWidth: liveText.implicitWidth + Style.space(14)
              implicitHeight: liveText.implicitHeight + Style.space(4)
              radius: height / 2
              color: "transparent"
              borderSpec: Border.flat(Color.accent, 1)

              Text {
                id: liveText
                anchors.centerIn: parent
                text: "LIVE"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
            }
          }
        }

        Text {
          visible: root.actionStatus !== ""
          width: parent.width
          text: root.actionStatus
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground }

        // Two platforms side by side. They are not the same shape — Android is
        // a device you reach out to, Apple is a receiver that waits — so they
        // get their own columns rather than one merged list.
        RowLayout {
          width: parent.width
          spacing: Style.space(14)

          PlatformColumn {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            columnIndex: 0
            glyph: "\uf17b"
            tint: "#3DDC84"
            label: "ANDROID"
            actions: root.androidActions
            emptyText: root.haveAndroid ? "" : "No device"
            emptyTip: "Turn on Settings → Developer options → Wireless debugging. "
                      + "scrcpy carries the mirror over adb, so this is needed even to view."
            note: root.discoveredName
          }

          Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.minimumHeight: Style.space(90)
            color: root.dim
            opacity: 0.35
          }

          PlatformColumn {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            columnIndex: 1
            glyph: "\uf179"
            rainbow: true
            glyphSize: Style.space(32)
            label: "APPLE"
            actions: root.appleActions
            emptyText: ""
            emptyTip: ""
            note: root.receiverStreaming ? "mirroring"
                  : (root.receiverRunning ? "waiting" : "")
          }
        }

        Column {
          visible: root.showInstall && root.qrSize > 0
          width: parent.width
          spacing: Style.space(8)

          Rectangle {
            id: qrCanvas
            // Integer module size keeps the code crisp; a fractional one
            // blurs the edges and phones stop reading it.
            readonly property int moduleSize: root.qrSize > 0
              ? Math.max(3, Math.floor(Style.space(190) / root.qrSize)) : 0
            width: root.qrSize * moduleSize
            height: width
            color: "white"
            radius: Style.cornerRadius
            anchors.horizontalCenter: parent.horizontalCenter

            Grid {
              anchors.centerIn: parent
              columns: root.qrSize
              Repeater {
                model: root.qrSize * root.qrSize
                Rectangle {
                  required property int index
                  width: qrCanvas.moduleSize
                  height: qrCanvas.moduleSize
                  color: root.qrRows[Math.floor(index / root.qrSize)]
                           .charAt(index % root.qrSize) === "1" ? "black" : "white"
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Scan with the phone's camera to install ScreenStream, "
                  + "then start it and press Find phone."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }

        Text {
          visible: root.receiverRunning && root.airplayPin === ""
          width: parent.width
          text: "AirPlay receiver has no PIN — anyone on this network can mirror here."
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component PlatformColumn: ColumnLayout {
    id: col
    property int columnIndex: 0
    property string glyph: ""
    property string label: ""
    property var actions: []
    property string emptyText: ""
    property string emptyTip: ""
    property string note: ""
    property color tint: root.foreground
    property bool rainbow: false
    property real glyphSize: Style.space(26)

    spacing: Style.space(8)

    // Fixed-height slot so both columns' labels sit on the same line even
    // though the two marks differ in height at equal weight.
    Item {
      Layout.fillWidth: true
      implicitHeight: Style.space(38)

      PlatformGlyph {
        anchors.centerIn: parent
        glyph: col.glyph
        size: col.glyphSize
        color: col.tint
        rainbow: col.rainbow
      }
    }

    Text {
      Layout.fillWidth: true
      text: col.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 2
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      Layout.fillWidth: true
      visible: col.note !== ""
      text: col.note
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    Item { Layout.fillWidth: true; implicitHeight: Style.space(4) }

    EmptyRow {
      Layout.fillWidth: true
      visible: col.emptyText !== ""
      text: col.emptyText
      tip: col.emptyTip
    }

    Repeater {
      model: col.actions
      ActionRow {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        action: modelData
        rowColumn: col.columnIndex
        rowIndex: index
      }
    }
  }

  component EmptyRow: CursorSurface {
    id: emptyRow
    property string text: ""
    property string tip: ""

    foreground: root.foreground
    implicitHeight: emptyLabel.implicitHeight + Style.spacing.rowPaddingX

    Text {
      id: emptyLabel
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      text: emptyRow.text
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    MouseArea {
      id: emptyHover
      anchors.fill: parent
      hoverEnabled: true
    }

    PanelToolTip {
      visible: emptyHover.containsMouse && emptyRow.tip !== ""
      text: emptyRow.tip
      fontFamily: root.fontFamily
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property var action: null
    property int rowColumn: 0
    property int rowIndex: 0

    hasCursor: root.cursorActive
               && root.cursorColumn === rowColumn
               && root.cursorIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill

    implicitHeight: rowInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.cursorColumn = actionRow.rowColumn
        root.cursorIndex = actionRow.rowIndex
      }
      onClicked: if (actionRow.action) root.activate(actionRow.action.key)
    }

    RowLayout {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: actionRow.action ? String(actionRow.action.glyph || "") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        Layout.fillWidth: true
        text: actionRow.action ? String(actionRow.action.title || "") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    // The detail that used to sit under every label lives here instead.
    PanelToolTip {
      visible: rowHover.containsMouse && actionRow.action
               && String(actionRow.action.tip || "") !== ""
      text: actionRow.action ? String(actionRow.action.tip || "") : ""
      fontFamily: root.fontFamily
    }
  }
}

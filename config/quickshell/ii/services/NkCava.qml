pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

// NovelKnock: one shared cava for the bar's music wave borders and the music sheet visualizer.
// Starting cava opens an audio capture stream (that is what made the sound hiccup), so there is
// only ever one, it starts with the music and stops 2 minutes after the music stops.
Singleton {
    id: root

    property list<real> points: []          // 50 values, 0 to 1000

    // Bar music wave settings (Super+A > Bar music wave), saved in ~/.config/novelknock/bar-wave.json
    property bool waveEnabled: true
    property real waveStrength: 3           // 1 subtle .. 6 wild
    function setWave(enabled, strength) {
        root.waveEnabled = enabled;
        root.waveStrength = Math.round(strength * 10) / 10;
        waveSaveTimer.restart();
    }
    Timer {
        id: waveSaveTimer
        interval: 300
        onTriggered: {
            Quickshell.execDetached(["mkdir", "-p", FileUtils.trimFileProtocol(`${Directories.config}/novelknock`)]);
            waveFile.setText(JSON.stringify({ enabled: root.waveEnabled, strength: root.waveStrength }, null, 2));
        }
    }
    FileView {
        id: waveFile
        path: FileUtils.trimFileProtocol(`${Directories.config}/novelknock/bar-wave.json`)
        onLoaded: {
            try {
                const c = JSON.parse(waveFile.text());
                root.waveEnabled = c.enabled !== false;
                root.waveStrength = Number(c.strength ?? 3);
            } catch (e) {}
        }
    }
    property bool sheetWanted: false        // set by the music sheet while its visualizer shows
    readonly property bool playing: MprisController.activePlayer?.playbackState == MprisPlaybackState.Playing
    // cava only runs for the music sheet, or for the bar wave when the wave is on (saves CPU when it is off)
    readonly property bool wanted: root.sheetWanted || (root.playing && root.waveEnabled)

    onWantedChanged: {
        if (root.wanted) {
            stopTimer.stop();
            cavaProc.running = true;
        } else {
            stopTimer.restart();
            root.points = [];
        }
    }
    Component.onCompleted: {
        if (root.wanted) cavaProc.running = true;
    }

    Timer { // stop cava 2 minutes after the music stops
        id: stopTimer
        interval: 120000
        onTriggered: {
            if (!root.wanted) cavaProc.running = false;
        }
    }
    Timer { // cava quit on its own (audio restarted): start it again if it is still wanted
        id: restartTimer
        interval: 3000
        onTriggered: {
            if (root.wanted) cavaProc.running = true;
        }
    }

    Process {
        id: cavaProc
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        onRunningChanged: {
            if (!running) {
                root.points = [];
                if (root.wanted) restartTimer.restart();
            }
        }
        stdout: SplitParser {
            onRead: data => {
                if (!root.wanted) return; // nothing shows it, skip the work
                root.points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }
}

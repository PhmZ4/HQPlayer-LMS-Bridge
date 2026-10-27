# HQPlayer Bridge — LMS Plugin

A plugin for **Lyrion Music Server** that presents each **HQPlayer** instance on your network as a native LMS player. Play to it, pause, seek, set its volume and see its artwork from Material or any control point, while HQPlayer does the upsampling, filtering and modulation exactly as it always has.

It replaces the `squeeze2upnp` UPnP bridge, with **no helper in the playback path and no audio stage of its own**. LMS and HQPlayer are both *pull* engines, so the bridge hands HQPlayer a URL pointing back at LMS and then stays out of the audio path — what crosses it is control messages, over HQPlayer's own XML control API, on one socket. That is why there is no buffer to tune, no transcoder to configure and nothing extra to run for playback.

There is one **optional** helper, for a different job: restarting HQPlayer from LMS, which you need after power-cycling an NAA endpoint. Playback never uses it. See [Restarting HQPlayer from LMS](#restarting-hqplayer-from-lms-optional).

Tested on LMS 9.x against **HQPlayer Embedded 6** feeding an NAA endpoint.

> **This is PhmZ4's fork** of [SimonArnold002/LMS-HQPlayer-Bridge](https://github.com/SimonArnold002/LMS-HQPlayer-Bridge), currently at version **1.3.0**, published as **HQPlayer-LMS-Bridge** to keep it apart from the original. It adds a [bit-perfect mode](#bit-perfect-mode), shows the **ReplayGain** setting on the player's Audio page, puts the [connection status](#connection-status) on the plugin's settings page, and shows HQPlayer's input and output buffers in the [live view](#seeing-what-its-doing). Everything else works as in the original. See [CHANGELOG.md](CHANGELOG.md).

### What's new in this fork (1.1.0 – 1.3.0)

- **A bit-perfect mode**, in *Player settings → HQPlayer*. While it is on there is no ReplayGain, no bitrate limit and no MP3 conversion; Lyrion's volume is set to fixed and HQPlayer is set once to 0 dB, or to its own maximum volume if that is lower. An optional *Native files only* switch skips anything Lyrion would convert (ALAC/AAC/M4A, or a relayed stream it transcodes). Since 1.3.0, a Qobuz FLAC that Lyrion relays without conversion counts as native.
- **A ✓/⚠ list** of every Lyrion setting that could alter the stream, and (1.1.1) whether Lyrion touched the last track played.
- **The ReplayGain setting is visible** on the player's Audio page.
- **The connection status** of each HQPlayer in *Settings → Plugins → HQPlayer Bridge*.
- (1.2.0) **HQPlayer's input and output buffers** in the live view.
- (1.3.0) **A Qobuz or Tidal FLAC that Lyrion relays without conversion counts as native**, so it plays bit-perfect under *Native files only*.

Every page of the plugin is also available in French.

---

## Features

| Feature | What it gives you | What you need to do |
|---|---|---|
| **Appears as a real player** | Each instance shows up in LMS's player list, ready to select | Nothing |
| **Found automatically** | Discovered on the network; nothing to configure for most setups | Nothing, if HQPlayer is reachable from the server. On another subnet or VLAN: *Settings → Plugins → HQPlayer Bridge*, choose **Only at the addresses below** and type its IP address |
| **No extra audio hop** | HQPlayer fetches the music itself — no buffer, helper or UPnP hop in between | Nothing |
| **Your library, untouched** | FLAC, WAV, AIFF, DSF/DFF, WavPack, MP3 and Ogg go over as the original file, including native DSD | Nothing. To be sure no gain or other change is applied on the way, turn on **Bit-perfect mode** (below) |
| **Everything else plays too** | ALAC, AAC and M4A are converted to FLAC by LMS on the way out | Nothing — unless **Native files only** is on, which skips them on purpose |
| **Streaming at full rate** | Qobuz and Tidal are fetched by HQPlayer straight from the service; Deezer and radio go through LMS. A FLAC relayed by LMS without conversion is still the original file | Install and sign in to the service's LMS plugin. Keep *Bitrate limit* at **No limit** on the player's Audio page, or relayed streams are turned into MP3 (bit-perfect mode keeps it there for you). For Qobuz/Tidal to be fetched directly and pre-queued, keep **Settings → Advanced → Network → Streaming mode for HTTP(S)** on *Normal streaming* |
| **Gapless** | Library and direct streaming hand the next track over early, so HQPlayer makes the join itself | Nothing |
| **ReplayGain everywhere** | Library *and* streaming normalised using exactly the figure LMS worked out | Choose a mode in **Player settings → Audio → Replay Gain** (shown there since 1.1.0), and leave bit-perfect mode off — it replaces every gain with unity |
| **Artwork on the endpoint** | Cover art reaches HQPlayer and its display, from your library or a service, served by LMS on your network at up to 600x600, and stays with its own track across a gapless hand-over | Nothing |
| **Volume, both ways** | The LMS slider moves HQPlayer, and HQPlayer's own volume moves the slider. HQPlayer's maximum volume is respected | Leave **Player settings → Audio → Volume Control** on *variable*. Bit-perfect mode sets it to *fixed* while it is on |
| **Pause from either end** | Pausing at HQPlayer or on the endpoint's remote pauses LMS too, within a second | Nothing |
| **Skip back from HQPlayer** | Skipping back to an earlier track in HQPlayer's own playlist while it plays moves LMS to that track too | Nothing |
| **Stable player identity** | Prefs and playlist survive HQPlayer changing IP address | Nothing |
| **Bit-perfect mode** | One switch per player: no ReplayGain, no bitrate limit, Lyrion volume fixed, HQPlayer set once to 0 dB or its own maximum. See [Bit-perfect mode](#bit-perfect-mode) | Open **Player settings → HQPlayer**, set **Bit-perfect mode** to *On* and save. Optionally set **Native files only** too. Set HQPlayer's own volume and maximum the way you want them |
| **What Lyrion could change** | A ✓/⚠ list of ReplayGain, bitrate limit, volume control and the route of the last track. See [What Lyrion could change](#what-lyrion-could-change) | Open **Player settings → HQPlayer**. Reload the page to refresh it |
| **Connection status** | Each HQPlayer's link, output mode, filter, shaper, transport and route, with what the bridge is still waiting for | Open **Settings → Plugins → HQPlayer Bridge**. It is a snapshot: reload to refresh, or follow its link to the live view |
| **Live view** | What's playing, transport, volume, the signal path and HQPlayer's **input and output buffers**, updating every second in your Material theme | Open **Apps → HQPlayer Bridge → HQPlayer Live View**, the link on either settings page, or `http://<your-LMS>:9000/hqplive` |
| **Restart HQPlayer from LMS** | One tap in Apps restarts HQPlayer, with your saved settings, e.g. after power-cycling your NAA endpoint | Install the optional restart helper on the HQPlayer machine (needs **Python 3.7+** there). See [Restarting HQPlayer from LMS](#restarting-hqplayer-from-lms-optional) |

---

## Requirements

- **Lyrion Music Server 8.0.0+**.
- **HQPlayer** with its control API enabled. Verified against HQPlayer Embedded 6; HQPlayer Desktop 6 has also been used, on a Mac.
- **HQPlayer must reach the LMS server over HTTP**, because it fetches the audio itself. Both on the same LAN is the normal case.
- For streaming, the matching service plugin installed and signed in.

Nothing else has to be set up on either side — no shared filesystem, no matching library paths, no audio device in LMS.

---

## Installation

**Via repository (recommended).** In LMS go to **Settings → Plugins → Additional Repositories** and add:

```
https://raw.githubusercontent.com/PhmZ4/HQPlayer-LMS-Bridge/main/repo.xml
```

If you used the original plugin's repository, or this fork under its earlier name (`.../PhmZ4/LMS-HQPlayer-Bridge/...`), remove that entry so that only one source offers updates.

Install **HQPlayer Bridge** from the plugin list and restart. Then open the player menu in Material — the HQPlayer instance is listed by name. Select it and play something.

**Manual.** Download [`HQPlayerBridge.zip`](https://github.com/PhmZ4/HQPlayer-LMS-Bridge/raw/main/HQPlayerBridge.zip) from this repository and unzip it so it sits as `Plugins/HQPlayerBridge/`:

```bash
sudo rm -rf /var/lib/squeezeboxserver/Plugins/HQPlayerBridge
sudo unzip HQPlayerBridge.zip -d /var/lib/squeezeboxserver/Plugins/
sudo chown -R squeezeboxserver:nogroup /var/lib/squeezeboxserver/Plugins/HQPlayerBridge
sudo systemctl restart lyrionmusicserver
```

---

## Settings

**Nothing to configure for most setups.** Out of the box the Bridge finds every HQPlayer on your network by itself, and a new one appears within about 15 seconds of being switched on.

**If automatic discovery can't find HQPlayer**, connect to it by IP address instead. That is usually because HQPlayer is on a different subnet or VLAN from the server, or on a network that blocks multicast. Open **Settings → Plugins → HQPlayer Bridge** (or the **Settings** row under HQPlayer Bridge in Apps) and set **Find HQPlayer** to **Only at the addresses below**, then type each HQPlayer's IP address into the box — separated by commas, spaces or new lines. Host names can't be used.

- **HQPlayer must be running at a new address when you save.** The Bridge connects to it first, and won't save an address nothing answers at — the page says *Checking…* while it does, which can take a few seconds.
- **The two modes are never mixed.** With addresses only, the Bridge sends no discovery traffic at all, and only the HQPlayers you listed are players. Switching back to **Automatically** clears the list, and discovery finds again whatever it can reach.
- **A player is identified by the name set in HQPlayer, not by its address.** Delete an address and save to remove its player; add it back, or replace it with HQPlayer's new address, and you get the same player back with its settings and playlist.
- **With addresses only, an HQPlayer whose address changes isn't followed.** Update its address in the box, or give that machine a fixed address.
- **Your choice is kept when the plugin updates.** An update never switches you back to automatic or clears your list.

### Connection status

The same page opens with the **connection status** of each HQPlayer:

```
Salon
  Control link               Connected - 192.168.1.20:4321
  Output mode                SDM
  Filter                     poly-sinc-gauss-xla
  Shaper                     ASDM7EC
  Output transport           id 0
  Source                     44100 Hz / 16 bit FLAC
  Output format              DSD 11.2 MHz
  Route of the playing track Playing the original file straight from Lyrion, untranscoded ...
  Gain on the last track sent +0.00 dB (bit-perfect)
  Bit-perfect mode           On
```

A link that is down, and a track that Lyrion converts or relays, are shown in red. If the bridge is still waiting for an HQPlayer, the page says so. This is a **snapshot taken when the page opens**: reload it to refresh, or follow its link to the live view, which updates every second.

---

## Restarting HQPlayer from LMS (optional)

**What it's for.** If you switch your NAA endpoint off and on again, HQPlayer often won't use it again until HQPlayer itself is restarted. Signalyst's advice is to start the NAA first, then HQPlayer. HQPlayer's **Refresh devices** button reconnects the endpoint but drops your saved output mode (SDM comes back as PCM). A restart reloads your saved settings. HQPlayer's control API has no restart command, so doing this from LMS needs a small helper on the HQPlayer machine.

**What it is.** `hqrestart` is one Python script (standard library only) in [`tools/hqrestart/`](tools/hqrestart/) of this repository. It is **not part of the plugin**, and playback works exactly the same without it. It listens on port **8090**. When asked, it restarts HQPlayer the same way it was started, as an app or as a service, on macOS or Linux (Windows is not supported). It never restarts anything by itself.

**Only tested on macOS so far.** It has been run end to end on a Mac, with HQPlayer Embedded running as an app. macOS with HQPlayer as a service, and Linux, are written and covered by automated tests, but have not yet been run on a real machine, so treat them as untried. The installer's question for your LMS server's address is new and is covered by those tests, but has not yet been run on a real install either.

**Using it.** Once the helper is running, **Apps → HQPlayer Bridge** shows a **Restart *name*** row under HQPlayer Live View. Tap it, then **Restart *name* now**. It answers once HQPlayer is back, which takes about 7 seconds on a Mac.

### What the helper needs

**Python 3.7 or later, on the HQPlayer machine.** The helper is a single Python script and uses
only the standard library — nothing to `pip install`. **The installer never installs Python for
you**; if it can't find `python3` it stops and says so, leaving your system untouched.

**On macOS, expect a prompt from Apple — not from this installer.** macOS ships no Python of its
own. `/usr/bin/python3` is a stub, so the first time anything runs it, macOS itself offers to
install the **Command Line Tools**:

> The "python3" command requires the command line developer tools. Would you like to install the
> tools now?

That dialog is Apple's. Accepting it installs the Command Line Tools (a developer package of a
few hundred MB, which includes Python 3.9) and the helper then installs normally. **If you would
rather not have that**, click *Not Now* and install Python another way first — the
[python.org installer](https://www.python.org/downloads/macos/) or `brew install python` — then
run `./install.sh` again. Either is fine; the helper only needs *a* `python3` of 3.7 or later on
your `PATH`.

**On Linux, nothing is offered and nothing is installed.** Practically every distribution ships
Python 3 already, so there is usually nothing to do. If it is genuinely missing the installer
stops with `python3 not found - install Python 3.7 or newer first`, and you install it with your
package manager (`sudo apt install python3`, `sudo dnf install python3`, and so on). No
equivalent of Apple's prompt exists, so a Linux install will never pull in a toolchain behind
your back.

### Install the helper

On the **HQPlayer machine**, with **Python 3.7 or later** (see above):

**Step 1.** Download this repository (**Code → Download ZIP** on GitHub) and open the `tools/hqrestart/` folder in a terminal.

**Step 2.** Run the installer that matches how HQPlayer runs there:

| HQPlayer runs as… | macOS / Linux |
|---|---|
| an app, or a Linux user service | `./install.sh` |
| a system service | `sudo ./install.sh --system` |

**Step 3.** It asks for your **LMS server's IP address**:

```
Lyrion server IP address (press return to skip):
```

Type it in. The plugin sends no token, so a restart is only accepted from an address the helper has been told to trust — without this the Restart row appears but every restart is refused. You can also give it up front, or change it later, by re-running the installer with `./install.sh --allow 192.168.1.234`; pressing return at the prompt keeps whatever is already set, so re-installing to pick up a new version never loses it.

It must be an IP address rather than a name, because it is matched against the address the request arrives from.

If a restart later says **Restart failed: bad or missing token**, the address LMS called from isn't in the list. The helper's log (below) names that address and the exact command to add it.

The helper then starts at once, and again at every login (app) or boot (service). The installer prints where it put the config file, `hqrestart.json`, the access token, and whether LMS is allowed to restart HQPlayer.

**Step 4.** Check it from the LMS machine: `curl http://<hqplayer-ip>:8090/ping` should answer with `"service": "hqrestart"`. The Restart row appears the next time you open the Bridge in Apps. An HQPlayer that has no helper yet is re-checked at most once a minute.

| | macOS | Linux |
|---|---|---|
| config (app) | `~/Library/Application Support/hqrestart/` | `~/.config/hqrestart/` |
| config (service) | `/Library/Application Support/hqrestart/` | `/etc/hqrestart/` |
| log | `~/Library/Logs/hqrestart.log` (`/Library/Logs/` for a service) | `journalctl --user -u hqrestart` (no `--user` for a service) |
| runs as | a LaunchAgent (LaunchDaemon for a service) | a systemd unit |
| listed in | System Settings → General → Login Items & Extensions → *Allow in the Background*, as **python3** | `systemctl --user status hqrestart` (no `--user` for a service) |
| process | **Python** in Activity Monitor | `python3 …/hqrestart.py` in `ps` or `top` |

**It doesn't appear under its own name everywhere.** macOS names the background item after the Python it runs, so it shows as *python3*, not *hqrestart*, and macOS tells you with a "Background Items Added" notice when you install it. If you switch that item off, the helper stops and the Restart row goes with it; use the uninstaller rather than the switch. The macOS column was checked on a real Mac; the Linux column describes what the installer sets up, and has not been seen on a real machine.

- **Linux, app mode:** the helper runs only while you're logged in, unless you run `sudo loginctl enable-linger <your user>` (the installer reminds you). If you run a firewall, open TCP 8090 to the LMS server.
- The helper can also be called without LMS, with the token, e.g. from a phone shortcut. See [`tools/hqrestart/README.md`](tools/hqrestart/README.md) for that and for every config option.

### Uninstall the helper

Run the installer from the same folder with the uninstall option, matching how you installed it:

| | macOS / Linux |
|---|---|
| app | `./install.sh --uninstall` |
| service | `sudo ./install.sh --system --uninstall` |

This stops the helper and removes it from startup. Your config folder (above) is left in place; delete it if you won't reinstall. The Restart row disappears from Apps when LMS next restarts.

---

## Bit-perfect mode

Open **Player settings → HQPlayer** for an HQPlayer player (in Material: the
player's settings, then the HQPlayer page). Set **Bit-perfect mode** to **On**
and save. While it is on, what leaves Lyrion for HQPlayer is the source,
unaltered:

- **No ReplayGain.** A unity gain is sent with every track. That overrides the
  file's own tags, so HQPlayer does not apply one from them either.
- **No bitrate limit.** Lyrion's limit is held at none, so nothing is ever
  turned into MP3 on the way.
- **Lyrion's volume is fixed.** The slider no longer moves HQPlayer. Switching
  the mode on sets HQPlayer's volume to 0 dB once - or to HQPlayer's own
  **maximum volume** if that is lower, so a -3 dB ceiling kept as headroom
  against inter-sample clipping is respected. HQPlayer's own volume, and the
  endpoint's knob, stay yours to change afterwards. Switching the mode off
  puts Lyrion's volume control back as it was.

**Native files only** (a second switch, used only with bit-perfect on) skips
anything Lyrion would actually **convert**: ALAC, AAC and M4A (transcoded), and
any stream Lyrion relays *and* transcodes by its File Types rules. Three skipped
in a row stop the player. Left off, those still play, and the page shows their
route in red.

**A relay is not a conversion.** Qobuz and Tidal are normally fetched by
HQPlayer straight from the service. When Lyrion will not allow that - its
*Streaming mode for HTTP(S)* (Settings → Advanced → Network) is not *Normal
streaming*, or a seek needs a FLAC header - the track goes through Lyrion's own
stream instead. If Lyrion's own decision for it is the passthrough rule (`flc
flc * *` → `-`, the default), the bytes are the service's original FLAC, and
since 1.3.0 the bridge treats that as native: it plays under *Native files
only* and shows a ✓. The only cost is that such tracks are not pre-queued for a
gapless join. Set the streaming mode back to *Normal streaming* to have
HQPlayer fetch Qobuz directly again; the page tells you when it is not.

### What Lyrion could change

The page also lists each Lyrion setting that could change what reaches
HQPlayer, read from where Lyrion itself reads it - ✓ when it changes nothing,
⚠ when it does. It is worked out when the page opens.

| Check | ✓ | ⚠ |
|---|---|---|
| **ReplayGain** | Bit-perfect on (unity sent), or ReplayGain off in Lyrion - HQPlayer may then still read the file's tags itself, if its own album-gain option is on | ReplayGain on: Lyrion's gain is sent and changes the level |
| **Bitrate limit** | None: nothing is turned into MP3 | A limit in kbps: anything going through Lyrion's own stream (Deezer, radio) is transcoded to MP3 to fit it. Library files and direct Qobuz/Tidal are never affected |
| **Volume control** | Fixed: Lyrion's slider does not move HQPlayer | Variable: the slider sets HQPlayer's volume. The bytes still arrive untouched - HQPlayer applies the level in its own processing - but the level is not the one you may expect |
| **Last track** | The original file, a stream HQPlayer fetched straight from the service, a stream Lyrion relayed **without conversion** - or a track *Native files only* skipped, so nothing converted reached HQPlayer. A neutral – means nothing has played since HQPlayer connected | Lyrion transcoded it (ALAC, AAC, M4A), or relayed it and transcoded it on the way |
| **Streaming mode for HTTP(S)** | Shown only when it is not *Normal streaming*, as information (–): Qobuz and Tidal are then relayed by Lyrion. Still bit-perfect when passed through, but not pre-queued | - |

The first three are settings; the last is what actually happened to the track
playing, or last played. Below the checks, the page shows this player's
connection status, including the **gain sent with the last track**. **What this does not change:** HQPlayer's own
processing - upsampling, filters, modulation - which is the point of HQPlayer.

---

## How your music reaches HQPlayer

The plugin picks the route per track. You don't configure any of this.

| What you play | How it gets there | Gapless |
|---|---|---|
| Library file HQPlayer can decode | The original file, byte for byte — nothing re-encoded | Yes, pre-queued |
| Library ALAC / AAC / M4A | LMS converts to FLAC and the plugin serves it on a route of its own | Yes, pre-queued |
| **Qobuz, Tidal** | The service's own URL, handed straight over — LMS stays out of the audio path | Yes, pre-queued |
| **Deezer, internet radio** | Through LMS on a plain path of its own, FLAC first so usually no transcoding | Next track loads at the end |

Everything is addressed by URL, so nothing about your files needs to match between the two machines.

Where a track is pre-queued, HQPlayer has the next one in its own playlist before the current ends and makes the join itself. A pre-queue HQPlayer is slow to acknowledge, or turns down outright, still reaches the next track — the bridge falls back to a normal load rather than losing it, and a stop at HQPlayer's own front end is told apart from the playlist simply running out. On the last route the next track loads when the current one finishes — about half a second, against roughly a second and a half of audio already in flight, so nothing is heard.

**ReplayGain** is set on the player's **Audio** settings page (it was hidden before 1.1.0, although the bridge already used it). It is sent with the track, exactly as LMS calculated it — nothing scaled or trimmed, and a *boost* goes through in full. This covers streaming, where there are no tags, and beats letting HQPlayer read library tags itself, which it does at the moment playback starts and so misses the first tracks of a fresh album. LMS's choice between album and track gain is the one you get. A track LMS has no figure for is left completely alone. If you have HQPlayer's **convolution gain compensation** set, that applies on top — deliberately not cancelled out. In [bit-perfect mode](#bit-perfect-mode) none of this applies: a unity gain goes with every track instead.

---

## Volume

HQPlayer holds the real level in dB and decides how to split it between the endpoint's hardware attenuator and its own software gain; LMS has an 0–100 slider. The two are kept in step both ways, within about a second.

**One LMS step is one dB, with LMS 100 being 0 dB.** The range is read from HQPlayer at connect, so a ceiling below 0 dB is handled.

The level you start with is **HQPlayer's own**, not one the plugin asserts. To stop Lyrion driving the volume at all, set **Volume Control: fixed** on the player's Audio settings page; the plugin honours that and never changes it for you. The one exception is [bit-perfect mode](#bit-perfect-mode): switching it on sets the volume control to fixed, and switching it off puts your earlier choice back. HQPlayer's own "fixed volume" is a *startup level*, not a lock.

---

## Seeing what it's doing

**HQPlayer Live View** — open it from **Apps → HQPlayer Bridge**, or pin it for a Material home-screen tile. It updates every second and shows what's playing, transport and volume controls, and the live signal path:

```
Control link       Connected - 192.168.1.109:4321
Source             44100 Hz / 16 bit FLAC
Output format      96000 Hz / 24 bit PCM
Filter             poly-sinc-gauss-long
Shaper             TPDF
Processing speed   30.3x realtime
Input buffer       [█████████░░░]  81 %
Output buffer      [███████████░]  94 %
```

**Input buffer** is how much HQPlayer has read ahead of its decoder, **Output buffer** how much is queued for the endpoint. A bar turns red below 15% while playing: a low input buffer points at the network or the source (Lyrion, the streaming service), a low output buffer at HQPlayer's processing or the link to the NAA. Stopped or paused, an empty buffer is normal.

**With more than one HQPlayer,** a row of names appears above the panel and you tap the one you want to see and control. **Auto**, the default, follows whichever instance is playing. Your choice is remembered in that browser, and a dot marks any instance that is playing but not currently shown. Every instance's signal path is listed below either way.

HQPlayer reports the filter *really* in use, so a 44.1 kHz album shows your 1x filter and a 96 kHz one your Nx filter. Source and output always describe the track actually playing — resolving what comes next never overwrites them early. The page follows Material's theme and icons and works on a phone in either orientation, and a streamed track's cover carries the service's badge, as Material shows it on its own lists (only where Material is installed). Until HQPlayer is found it says it is waiting for the player to connect. It costs HQPlayer nothing — the values are already in memory from the status stream the plugin subscribes to.

**The plugin's settings page** shows the same facts as a snapshot - see [Connection status](#connection-status) - and each player's **HQPlayer** page shows its own, along with the [bit-perfect](#bit-perfect-mode) checks.

**The Apps entry** behind it is a browse list, which Material draws once and never refreshes, so it shows HQPlayer's **settings** — output mode, filter, shaper, transport id — rather than moving numbers that would go stale. It reports the transport **id**, not your endpoint's name: HQPlayer doesn't expose the NAA name over any control command.

---

## Known limitations

- **A switched-off HQPlayer's player stays listed for about 5 minutes.** That is Lyrion's own grace for a player that disconnects, so a restart or a network blip doesn't cost you the player's playlist. A player whose HQPlayer is still connected is never removed. The Bridge looks for new HQPlayers every 15 seconds (more often while it has found none), so one you switch on appears within about 15 seconds; one that is already a player reconnects by itself within 10.
- **A silent output-format mismatch is HQPlayer's to report.** If its output format is something your endpoint can't accept, it reports itself as playing and answers every command while rendering nothing. That can't be detected over the control API — the evidence is in HQPlayer's own log (`NAA output requested format not available!`). If a track looks like it's playing but you hear nothing, check the output format there first.
- **A sample-rate change between tracks is audible**, on every route. HQPlayer needs a couple of seconds to retune its output.
- **Radio track names are right when the stream starts, then stop updating.** HQPlayer's control API can't change the metadata on an item already playing, and re-sending it would restart the stream. LMS itself keeps up to date as usual.
- **HQPlayer Desktop switches its network control off when the computer's IP address changes.** It then can't be found or controlled until you switch it back on — the network button on HQPlayer's toolbar.
- **If the Bridge loses touch with HQPlayer mid-track, LMS stops.** That happens when HQPlayer restarts, or after a network drop. Nothing is sent while the link is down. When it comes back, HQPlayer is stopped too if it is still playing the track LMS gave it. Nothing starts again by itself: press play, and the track loads from its start. HQPlayer has to be sent the whole stream, so playback can't pick up part way through.
- **Music started from HQPlayer's own screen is left alone.** LMS doesn't follow it or try to take it over. Press play in LMS and it loads its own track again.
- **A skip back made in HQPlayer while it is paused isn't followed.** HQPlayer moves to the earlier track, but LMS stays on the one it was paused on. Skip back while it is playing, or skip in LMS.
- **HQPlayer's repeat setting is turned off** whenever the control link comes up. LMS owns the queue and needs to see HQPlayer's playlist end; with repeat on it never does. Set repeat and shuffle in LMS.

---

## Not supported

- **Selecting HQPlayer's DSP settings.** Filter, shaper, modulator, output mode and rate are set in HQPlayer, as before. The plugin reports them but cannot change them.
- **Browsing HQPlayer's own library.** Music comes from LMS; this makes HQPlayer a destination, not a source.
- **HTTP authentication.** If your LMS server is password-protected, HQPlayer can't fetch the audio URLs it's given.
- **Sync groups.** An HQPlayer player can't be synced with other players, and a sync group that includes one won't play. Play HQPlayer on its own.
- **One HQPlayer on two network interfaces at once** (for example wired and Wi-Fi together). HQPlayer itself supports one interface, and so does the Bridge: an HQPlayer reachable at two addresses can show up as two players.

---

## Licence and attribution

This plugin is released under the **MIT licence** — see [LICENSE](LICENSE).

The original plugin is by **CrystalGipsy** ([SimonArnold002/LMS-HQPlayer-Bridge](https://github.com/SimonArnold002/LMS-HQPlayer-Bridge)). This fork, from 1.1.0, is maintained by **PhmZ4**. Report problems with the 1.1.0 additions [here](https://github.com/PhmZ4/HQPlayer-LMS-Bridge/issues), not to the original author.

**It is not affiliated with, endorsed by, or supported by Signalyst.** For
anything to do with HQPlayer itself, go to Signalyst, not here; and please don't
take a problem caused by this plugin to them.

**HQPlayer** and **Signalyst** are trademarks of their respective owner. They are
used here only to identify the software this plugin works with.

The control protocol was implemented with reference to **Signalyst's own
`hqp-control` source**, © 2011–2026 Jussi Laako, which Signalyst publish under
the MIT licence. A copy is included in this repository at
`hqp-control-601-src/` together with its licence (`COPYING`); it is reference
material only and none of it is compiled into or shipped with the plugin. The
HQPlayer Control API is offered by Signalyst for exactly this purpose —
"implementing a custom GUI or other type of front-end utilizing the HQPlayer
playback engine".

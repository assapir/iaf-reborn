# Multiplayer — research

This page records how the original game's multiplayer works and how the port could build it. It is research only:
no multiplayer code exists yet (docs/status.md "Multiplayer"). Functions are v1.1 addresses (`FUN_xxxxxxxx`).
Research date: 2026-10-20.

**Terms**
- **Host / client:** the player who opens a session / a player who joins it. The exe calls them master and slave.
- **Session:** one hosted game, from the lobby to the end of the mission.
- **Owner:** the machine that simulates a unit; the other machines show a copy of it.
- **CommJnet:** the exe's own network library (its source paths are `C:\IafPatch\CommJnet\*.cpp`).
- **SAP:** the IPX service advertising protocol. **SPX:** IPX's stream protocol.
- **Sources:** a footnote names each outside source. "Inferred" marks our own reasoning from the decompile or the
  sources; "open" means nothing was found.

**Key facts**
- The exe does **not** use DirectPlay. It loads `wsock32.dll` at run time and runs its own protocol over TCP/IP or
  IPX/SPX (§2.1).
- TCP/IP: game data over TCP port 1791, session search by UDP broadcast on port 1791, or join by IP address.
- Up to 8 players. Each player owns their own jet; the host owns everything else (AI, ground units, mission
  scripts) (§2.4).
- The version check is a session tag, `IAF11` in v1.1 (`IAF01` in v1.0) (§2.6).
- Recommendation: our own protocol between our clients, with the original's authority split; no wire compatibility
  with the original exe (§3).

## 1. What the original offers

From the manual (EN 7.1–7.7, HE p57–63, as summarised in [manual-audit.md](manual-audit.md) §1 row 10 and §2 rows
2–5), the install's menu data and the v1.1 release notes (`assets/install/readme1_1.txt`):

| Area | What the original does |
|---|---|
| Players | 2 to 8[^moby][^lan], on a LAN or the internet. |
| Connection | IPX ("LAN only", `dctype1.trx`) or TCP/IP (`dctype2.trx`). Reviews also name Jane's Combat.Net[^combatsim][^wiki]. |
| Modes (`netmis.trx`) | **Special**: six missions made for multiplayer (511–516). **Campaign**: any campaign mission. **Custom**: a Mission Creator mission (666, `0x29a`). **All-Out War**: "every man for himself" (777); the player picks one of eight jets (`netaow.trx`), MiG-23 and MiG-29 included. |
| Special missions (`dmps1..6.trx`) | 511 an SA-6 site, 512 a naval force in the Dead Sea, 513 the control towers, 514 the tanks, 515 two convoys racing to a helicopter, 516 the nuclear reactor. Each is one side attacking, the other defending. |
| Sides | Blue or Red (`side.trx`). A taken formation offers to join as wingman. |
| Chat | `~` to all, Alt+`~` to friends, Shift+`~` to enemies, Ctrl+`~` to the target; Enter sends, Esc cancels. |
| Canned messages | F1–F12 (`resource/messages/chat_messages.trx`): Roger, Negative, "I'm in trouble. Help me!", "Attack % bearing %, % miles", Follow me, "Break! Missile!", "We're bugging out", "Watch my back!", "Attack! I'll cover!", "Stop shooting! I'm on your side!", "I'd better fly civilian jets...", "How does it feel to eat lead?". The same file holds automatic lobby lines (join, leave, mission loaded, ready to fly, jet chosen, joined red / blue side, no locked target). |
| Re-entry (custom missions) | count 0, 1, 2, 3 or unlimited; wait 0, 10 or 20 s; weapons guns only, as at death, or full reload. v1.1: a player rejoins at the previous location. |
| Debrief | "Blue side wins." / "Red side wins." (msgs 53 / 54). Custom and All-Out War give no score; every number but the pilot's score shows "N/A" (docs/front-end.md §13.14). |
| v1.1 additions | kill credit when the pilot ejects; each player's callsign above the plane; the version check (§2.6). |
| Preferences | In multiplayer the readers ignore the cheats: AI = Normal, stalls and spins on, easy landing on; the ini key `[Multiplayer] PreferencesApply` lets Invulnerable / No crashes apply (docs/front-end.md §12.3, docs/flight-model.md §15.7). |

Session messages (`menu/txt/msgs.trx`): 11 "quit the session?", 12 "Do you want to rejoin?", 15 "Lost contact with
host.", 16 "Session terminated by host.", 17 "Last player left the session.", 32 / 33 failed to join / create, 34
"Session closed", 42 "Session name already in use!", 43 "Session is closed!", 45 "A controllable jet should be
assigned to each player.", 48 "At least one jet needs to be selected for the opposite side.", 56 the version message.

## 2. How the exe does it

### 2.1 Transport
- **No DirectPlay.** The exe imports no `dplay*.dll`. `FUN_0055ce00` loads `wsock32.dll` with `LoadLibraryA` and takes
  every socket call by `GetProcAddress` (WinSock 1.1, "Needed Windows Sockets version 1.1"). So the DirectPlay
  Windows feature, DirectPlay wrappers and the DirectPlay specifications[^dpl4cs] do not apply to IAF (inferred).
- Two modes, logged as `CommJnet::init(MP_NET_TCP_PLAY)` and `MP_NET_SPX_PLAY`. A driver table (`DAT_00840090`)
  holds the per-mode socket functions.
- **TCP/IP:**
  - Game and session traffic: TCP, port **1791** (`0x6ff`, `FUN_0055c680`; `FUN_0055c6e0` binds and listens with
    backlog 5, `FUN_0055c520` reads the local addresses).
  - Session search: a UDP socket with `SO_BROADCAST` on the same port (`FUN_0055e7e0`). The broadcast address is the
    **classful** one of the local address (`FUN_0055c9d0`: class C → /24, B → /16, A → /8), not 255.255.255.255.
  - Direct join: "Enter IP address:" on the LAN screen (`FUN_00509510` → `FUN_00553d30`), timeouts
    `JoinRemoteIpTimeout` / `JoinFailedTimeout` = 2500 ms.
- **IPX/SPX:** SPX stream socket 0x87EC (`FUN_0055cb30`), SAP on the standard socket 0x0452 (`FUN_0055eba0`).
- A comm thread (`DAT_006992f8`, `FUN_00553910`) does the socket work. The game hands it each outgoing message by
  `PostThreadMessageA(0x4dd)` in a 0x50-byte block (`FUN_00556080`), so one message is at most 0x44 bytes.
- Settings in `iaf.ibx [Communication]` (`FUN_00554db0`): `PlayerListSwitchTimeMsec` 1000, `TimeToDelSessionMsec`
  10000 (a found session is dropped after 10 s without news), `DefaultSessionJoinState` 1, the join timeouts,
  `JoinDirectAutoJoinDelayMsec` 400, `JoinDirectWait` 400, `CommThreadPriorityIsHigh` 1, `CommEventsByThread` 0,
  `ChatMsgsFile`.

### 2.2 Packet layer (CommJnet)
- Every packet starts with a 4-byte header: u16 type, u16 total length (`FUN_0055e3b0`). Most types have a fixed size
  from the table at `0x665c10` (payload bytes: 0x09 → 4, 0x0b → 4, 0x11 / 0x12 → 8, 0x14 → 62, 0x1c → 70, 0x1d → 120,
  0x1e → 8, 0x20–0x22 and 0x24 → 84); text and list packets set their own length (`FUN_0055dd80`).
- A TCP read waits up to 1 s for a whole packet (`FUN_0055e4f0`).
- UDP datagrams (`FUN_00559380`): type 2 asks "who hosts?"; the host answers with type 0x14 (`FUN_0055b9b0`) whose
  name is `EAGAME.<tag>.<session name>` (`FUN_005588b0`, parsed by `FUN_00558910`). Type 0x18 is a second reply form
  (meaning open).
- Host-side TCP handler `FUN_0055ba10`, client-side `FUN_0055a560`. Known types:

| Type | Meaning |
|---|---|
| 0x0b | disconnect, with a reason; reason 6 drops the player |
| 0x0c | join request / player accepted (inferred) |
| 0x0d | the host starts the game: the client switches its sockets to the game-data handler `FUN_00558c40` (event "MPE_PLAY_GAME") |
| 0x11 / 0x12 | an 8-byte handshake (meaning open) |
| 0x16 / 0x17 | a text line (0x17 is relayed by the host as 0x16), e.g. "'%s' lost connection with '%s'" |
| 0x19 | the host sends the player list (`0x1f`) to a new client |
| 0x1c | the client's player number and address |
| 0x1d | handled by `FUN_0055bd80`, one of the session-tag functions (docs/front-end.md §17) |
| 0x20 / 0x21 | a player joined / left (inferred) |
| 0x22 | another client introduces itself: clients connect to each other, so the game runs as a **full mesh** of TCP links (inferred from `FUN_0055a560` and the per-player sends in §2.3) |
| 0x23 | the player list |
| 0x24 | the session status (player count; above 100 = closed), event 0x10 in `FUN_00556130` |

- Each peer link has 10 KB send / receive rings (`FUN_00558390`). In game mode, packets of type 5 carry the game
  messages (`FUN_00558fc0`; inferred from the length handling).
- The library reports to `FUN_00556130` (events MPE_PLAYER_CONNECTED, MPE_CONNECT_FAILED, MPE_PLAY_GAME,
  MPE_PLAYER_LIST_DISCONNECT …). The host rejects players beyond the free slots (`NET_MasterRejectPlayer`).

### 2.3 Game messages
- A game message is a C++ event object (base ctor `FUN_00450d60(id, destination)`, vtable `0x600a18`). Code posts it
  with `FUN_00445210` to the dispatcher `DAT_006992e4` (`FUN_005bf370`, vtable `0x6125f0`).
- Destination 9 means every other player; the dispatcher (`FUN_005bf500`) then sends one copy to each player 1–8
  that is present (`FUN_005bf3b0`), else to the one player named.
- The message is **bit-packed** (`FUN_00552410` writes n bits). The common header (`FUN_00445530`): 4 bits sender
  player, 1 bit "system message", 6 bits message id. Most messages then carry the unit's 32-bit network id
  (unit `+0x30 → +0x18`).
- Receive: `FUN_005bf620` reads the header and looks the id up in the table at `0x677488` (36 rows of 0x18 bytes:
  id, handler kind, …, a class 1–5 that sets the send cost in `FUN_005541e0`). Handler kinds: 0 = the multiplayer
  manager (`FUN_00542a30`), 2 = the unit with that id (`FUN_00439be0`), 3 = `FUN_004d18b0`, 4 = a window message
  replayed with `SendMessageA` to the main window.
- A message is sent only in a network game (`DAT_0082f398`) and only by the unit's owner (§2.4).

| Id | Sent by | Content |
|---|---|---|
| 0x00 | the multiplayer manager (`DAT_00699350`, ctor `FUN_00540af0`) | a lobby / session command, sub-code at `+0x14`, about 35 sub-codes (`FUN_00542690`; e.g. 0x25 `FUN_00540e90`) |
| 0x02 | (kind 4) | a front-end / window message relayed to the other players |
| 0x08 | RWR lock / unlock `FUN_0044deb0` / `FUN_0044e030` | emitter id, lock flag (docs/rwr.md §2) |
| 0x0c / 0x0d | AI manoeuvres `FUN_005d1100`, `FUN_005d9290`, `FUN_005dd4a0` | a manoeuvre state or point, so copies fly the same manoeuvre (inferred) |
| 0x10 | the player's controller `FUN_0044a240` | a cockpit command, e.g. each eject press (docs/mission-runtime.md) |
| 0x11 | systems damage `FUN_0044d760` | the damage code |
| 0x13 / 0x14 | the flight model, `FUN_005aebc0` | the jet's state, **every 0.2 s** (FM `+0xca0` = 0.2, `FUN_005a30b0`): id, 3 × 22-bit position, 3 × 15-bit attitude, a 30-bit value; 0x14 adds a few small fields (one is the wingtip-vortex flag, docs/flight-model.md §15) |
| 0x15 | ballistic weapons `FUN_005cbd80` | position |
| 0x16 | the flight model, `FUN_005aebc0` | one 22-bit value every 10 s (meaning open) |
| 0x17 | missile chase motion `FUN_005cc5e0` | the missile's state |
| 0x1b | `FUN_004a9470` | a unit switches to player control |
| 0x1c / 0x1d | `FUN_004a5250` (ScriptList::Jump, docs/mission-runtime.md) | a mission script jumps to motion / trigger entry n |
| 0x1e | the hit handler `FUN_004a97b0` | a hit on a unit this machine does not own, sent to its owner with the damage |
| 0x21 | the wingman radio | a command to a remote wingman (docs/radio.md) |
| 0x24 | `FUN_004bfd10` (at mission load) | open |

The scale of the packed position and attitude fields is open (the `__ftol` arguments are not traced).

### 2.4 Who decides what
- Every unit has an owner record (`FUN_00445190`): +8 = "simulated here", +0xc = the owner's player number.
- On the host (`DAT_0082f39c`) and in single player every unit is local. On a client every unit made at mission
  load is remote, owned by the host (`DAT_0062e534`). So **the host simulates the AI aircraft, ground units, SAMs and
  the mission scripts**, and sends script jumps (0x1c / 0x1d) and AI manoeuvres (0x0c / 0x0d).
- **Each player owns their own jet** (0x1b at the switch to player control) and sends its state at 5 Hz. A remote
  jet runs no physics (`S+0x00 == 0`, docs/flight-model.md §15), only the state send / receive; the FM keys
  `MultiplayerRoll/Pitch K/Beta` (9, 0, 9, 0) smooth the copy.
- **Damage:** contacts with a remote unit do nothing (`FUN_0043b340`). A hit on a remote unit goes to its owner as
  0x1e; the owner applies it (`FUN_004a9970`). So the owner decides the damage and the kill. v1.1 keeps the last
  shooter when the pilot ejects (`FUN_004a8ae0`, docs/damage.md §4).
- **Mission result:** in network play `PlayerN` entities get role 2 (neutral) (docs/mission-runtime.md §1); the
  debrief names the winning side. Who decides the result: the host (inferred; open).
- AI skill: in network play the AI is at Normal (docs/ai.md §13).

### 2.5 Clocks
- "System" messages (header bit set) carry a clock sync (`FUN_00552d00` sub-cases 0–4). `FUN_00553140` sends a
  time request to each player; `FUN_00553200` corrects the clock when the offset is above 100 ms. The result goes
  to the game clock setter (`param_1+0x7c`). So all machines run on the host's clock (inferred).
- Message timestamps are sim time; the dispatcher stamps each send (`FUN_005bf4a0`).

### 2.6 Session flow and the version check
- Screens (docs/front-end.md §1): Main → **0x15 CType** (IPX / TCP) → **0x16 TCP** or **0x17 IPX** (Callsign,
  Host, Join, Start; `FUN_00509510`) → **0x18 NetMis** (Special, Campaign, Custom, AllOutWar) → the mission list
  (0x1c SpMMis), **0x1d Side** or **0x1b NetAOW** (jet) → the multiplayer TSD (`mptsd.trx`, in flight
  `mpflytsd.trx`) → Arm → fly. Chat is the window `chat_t` (`FUN_004f83b0`).
- **Host** (`FUN_00555530`): the session name ("Enter new session name :", default `Session%03d`, `FUN_00553b90`;
  "." is replaced by ":"), then `FUN_0055b040(name, "IAF11")` opens the listen socket and the datagram socket. The
  host is player 1.
- **Join** (`FUN_005556a0` → `FUN_005597d0`): from the found-session list (8 entries, `FUN_00555130` drops stale
  ones) or by IP. An automatic retry runs once (`JoinDirectAutoJoinDelayMsec`).
- On a client the BACK plate is blank (docs/front-end.md §2); MAIN asks msg 11 and leaves the session.
- The row-disable check at `50a5f4` (docs/front-end.md §13) and the Arm slot checks are not traced (open).
- **Version check:** the tag comes from `FUN_00553ef0` ("IAF11"). The host puts it in its UDP reply; a joiner compares
  it with its own (`0x60cd38`, in `FUN_00559380`). On a mismatch it shows msg 56 once (`FUN_004e3f60(0x38)`). A v1.0
  joiner filters v1.1 hosts out of its list ("Host not found"), as the release notes say.

## 3. What our port would need

### 3.1 The pieces it touches

| Piece | Today | Multiplayer adds |
|---|---|---|
| Flight model (`crates/iaf-flight`) | steps the player's jet with the frame time (`terrain_view.gd`) | a remote-jet mode: no physics, follow received states with the Multiplayer smoothing gains; state export at 5 Hz |
| AI (`game/ai/`, `crates/iaf-flight/src/autopilot.rs`) | every AI flight runs locally | runs on the host only; clients show copies |
| Mission runtime (`game/mission/mission_runtime.gd`) | scripts, triggers, win / lose | host only; script jumps and the result go to clients; `PlayerN` role 2 |
| Damage (`game/mission/damage_model.gd`, `player_damage.gd`) | applied where the hit happens | applied by the owner; hit messages; kill credit with the eject rule |
| Weapons (`crates/iaf-avionics`) | local missiles, rounds, RWR | missile / bomb states from their owner; RWR lock messages |
| Front end (`game/menu/front_end.gd`) | screens 0x15–0x18, 0x1b, 0x1d are not built | the lobby, side / jet choice, the MP TSD, chat, MP debrief |
| Preferences (`game/settings.gd`) | local prefs | the multiplayer overrides (§1) |

### 3.2 Option (a): our own protocol between our clients
- Transport: Godot's ENet (`ENetMultiplayerPeer`, UDP with reliable and unreliable channels). LAN search by UDP
  broadcast (`PacketPeerUDP`), as the original; join by IP for the internet. WebSocket is not needed (no browser
  build).
- Message definitions and the state packing belong in a new Rust crate (rule of placement); Godot only moves bytes.
- Keep the original's authority split (§2.4): it is simple and fair, and needs no lock-step. Own jet state on an
  unreliable channel at 5 Hz (original), events (hits, kills, launches, script jumps, chat) on a reliable one.
- One topology: host relays (a star). The original's full mesh exists for 1998 LAN latency; a star is simpler with
  ENet and NAT (inferred).
- IPX: the IPX button maps to the LAN search (an IPX stack does not exist on modern systems; Linux removed it in
  4.18[^lkmlipx]). Record it in docs/deviations.md.
- Risk: low. All parts are ours; the hard part is the game rules, not the transport.

### 3.3 Option (b): wire-compatible with the original exe
- The target is CommJnet, not DirectPlay: TCP 1791 + UDP broadcast, the packet types of §2.2, then the bit-packed
  messages of §2.3.
- What it would take:
  1. The session layer: about 25 packet types, their exact byte layouts (most are only partly known), the mesh
     links, the clock sync.
  2. The 36 message ids bit-exact, including the open scales and the window messages that id 2 relays (raw exe
     window message numbers).
  3. The same network ids for every unit (mission-load order).
  4. When the original hosts, our client must fly AI copies from manoeuvre messages (0x0c / 0x0d), so our AI
     manoeuvres must match the exe's closely. When ours hosts, the original expects the same.
- Players: the original runs today only on a LAN or VPN. TCP/IP mode should work over Hamachi or ZeroTier, and IPX
  through IPXWrapper[^ipxw] (inferred; no report found). PCGamingWiki says the common no-CD fix breaks multiplayer[^pcgw].
  So the audience for mixed games is very small.
- Verdict: feasible in principle (the transport is small and plain WinSock), but it needs a full packet trace of
  two original exes (under Wine, TCP mode) and bit-exact game semantics. Several months of work for few players.

### 3.4 Recommendation
Build **option (a)**. Keep this page's protocol notes so a bridge for (b) stays possible later. Steps, with a
rough size each:
1. **Transport and lobby (medium):** the Rust message crate, ENet host / join, LAN search, the CType / TCP / IPX
   screens, callsign, session name, the player list, the version check (our version string instead of `IAF11`).
2. **Remote jets (medium):** own-jet state at 5 Hz, the remote-jet mode in `iaf-flight` with smoothing, callsigns
   above the planes, a two-instance headless test.
3. **Host authority (large):** AI, ground units and mission scripts on the host; copies on clients; script jumps;
   `PlayerN` role 2.
4. **Combat (large):** owner-applied hits and kills, missiles and bombs from their owner, RWR locks, the eject kill
   credit.
5. **Session rules (medium):** sides, slot checks (msgs 45 / 48), Special / Campaign / Custom / All-Out War, re-entry
   rules and rejoin, the multiplayer preference overrides.
6. **Chat and debrief (small):** `~` chat with its modifiers, F1–F12 and the automatic lines, the MP debrief (winning
   side, "N/A").

## 4. Open questions
- The byte layout of most CommJnet packet types (0x0c, 0x11, 0x12, 0x1c, 0x1d, 0x20–0x24) and of UDP type 0x18.
- The scales of the packed position / attitude fields in 0x13 / 0x14, the 0x16 value, the 0x14 extra fields.
- The ~35 sub-codes of message 0 (lobby commands) and what messages 0x03 (kind 3) and 0x24 carry.
- Who decides the mission result and the debrief, and how campaign missions assign players to formations.
- The re-entry rules' code (wait, weapons, count) and the rejoin "previous location" path.
- Chat: which message carries a chat line, and how Alt / Shift / Ctrl+`~` pick the receivers.
- The row-disable check at `50a5f4` and the multiplayer Arm slot checks.
- Whether the original plays over the internet through NAT today (Hamachi / ZeroTier / GameRanger / Kali): no report
  found. Kali runs IPX games over the internet[^kali]; whether IAF is on its list is open.
- Jane's Combat.Net support (1998–2002)[^wiki]: whether it used the same CommJnet TCP mode.

[^combatsim]: Thomas Spann, "Jane's IAF" review, COMBATSIM (1998-09-12): http://www.combatsim.com/review.php?id=280
[^wiki]: Wikipedia, "Jane's IAF: Israeli Air Force": https://en.wikipedia.org/wiki/Jane%27s_IAF:_Israeli_Air_Force
[^moby]: MobyGames, "Jane's Combat Simulations: IAF": https://www.mobygames.com/game/2720/janes-combat-simulations-iaf-israeli-air-force/
[^lan]: LAN gaming database, "Jane's Israeli Air Force": https://lan-gaming.codeberg.page/games/janes-israeli-air-force/
[^pcgw]: PCGamingWiki, "Jane's Israeli Air Force": https://www.pcgamingwiki.com/wiki/Jane's_Israeli_Air_Force
[^ipxw]: IPXWrapper (Daniel Collins), IPX/SPX over UDP for WinSock 1.x programs: https://github.com/solemnwarning/ipxwrapper
[^lkmlipx]: "staging: ipx: delete it from the tree", Linux 4.18 staging pull: https://lkml.iu.edu/hypermail/linux/kernel/1806.1/00758.html
[^kali]: Wikipedia, "Kali (software)": https://en.wikipedia.org/wiki/Kali_(software)
[^dpl4cs]: Microsoft, MC-DPL4CS "DirectPlay 4 Protocol: Core and Service Providers":
    https://learn.microsoft.com/en-us/openspecs/windows_protocols/mc-dpl4cs/10eeb2a2-da0e-4ce2-98dc-ba1a87092a68

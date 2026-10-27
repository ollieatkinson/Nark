# Nark

A minimal macOS app firewall with a [SwiftTUI](https://swifttui.sh/) terminal monitor. Written in Swift 6, using TCA 1.26.2 for feature state and SwiftLexicon for the shared vocabulary, message sending, and observation.

The development-signed filter is installed and live monitoring and blocking have been verified on this Mac. A temporary rule scoped to `/usr/bin/curl` and `example.com` caused connection failure and recorded blocked flows; removing it restored connectivity.

## Xcode project

Open `Nark.xcodeproj` with Xcode 27.2 or later. Its configuration is the native, hierarchical JSON `project.xcproj` format; there is no legacy `project.pbxproj` or project generator. App folders use native buildable folders, so adding a bootstrap source does not require enumerating it in the project file.

The project contains only the host app and system-extension targets, package product links, embedding, and signing configuration. Both targets link local Swift package libraries. The entry points in `App/Nark` and `App/NarkFilter` are eight lines each; app behavior, activation, terminal rendering, filtering, and messages live in `Sources`.

Copy `Configuration/Signing.example.xcconfig` to `Configuration/Signing.local.xcconfig` and set your team. The local file is ignored by source control. `Configuration` contains the shared Info.plist and entitlement templates used by both Xcode and the CLI packaging script. The project expects development profiles named `Nark macOS Development` and `Nark Filter macOS Development`; override the target's profile setting if using other names.

```sh
DEVELOPER_DIR=/Applications/Xcode-27.2.0-Release.Candidate.app/Contents/Developer \
  xcodebuild -project Nark.xcodeproj -scheme Nark \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData build
```

Approve the pinned Point-Free compiler macros in Xcode when prompted. Package tests remain runnable independently with `Scripts/test.sh`. The shared Xcode scheme runs live `status` in the debug console. Use a terminal for the interactive monitor, and the installed app's executable for activation.

## Build and run

Requires macOS 15+, Swift 6.4 (Xcode 27.2), and a sibling checkout of [Lexicon](https://github.com/ollieatkinson/Lexicon) at `../Lexicon`. The local dependency is intentional while shaping the shared vocabulary against the user's current library. SwiftPM builds the vocabulary generator and SwiftLexicon; optional MLX products are not linked into Nark.

```sh
source Scripts/environment.sh
xcrun swift build --disable-sandbox
Scripts/test.sh
/Applications/Nark.app/Contents/MacOS/nark watch
```

`--disable-sandbox` is needed in the current development environment because nested SwiftPM sandbox creation fails. A normal local development environment can omit it. Tests use Swift Testing (`import Testing`, `@Test`, and `#expect`) bundled with Xcode 27.2; no separate Testing package is needed. `Scripts/test.sh` selects that toolchain without changing the system's Xcode selection.

The default home view shows mirrored upload/download history above an application tree and offline world map. The graph shows current rates and a five-minute window, scoped to the selected application or executable service. Expand an app to see its executable services, destinations and individual retained connection records. Helpers inside an app bundle are grouped with that app; system executables are grouped under System services. Selecting any level highlights its peer countries and destination markers. Locations are approximate country centres; the map draws no routes or connecting lines. Local and unknown destinations have separate labels.

Colors follow the terminal's detected appearance rather than forcing a dark background. `NarkUI` uses SwiftTUI's value-type `Theme` and deferred styles such as `.theme.foreground`, `.theme.background`, `.theme.success` and `.theme.danger`. Text rows retain shape styles until rendering; charts and the map derive their drawing colors from the same terminal appearance. `Theme.light` and `Theme.dark` provide concrete presets, with `.light.foreground` and `.dark.foreground` available for explicit local styling. Normal monitor rendering uses the detected terminal theme.

Home colours use current policy: blocked sites have a red ×, mixed groups are amber, and the selected item shows ALLOW/BLOCK/MIXED. Tree rows and map markers update when a rule changes, without waiting for new traffic. Recorded verdicts remain available in connection details.

Click a row to select it, or its disclosure marker to expand/collapse. Up/Down select; Right expands or enters a branch; Left collapses or returns to the parent. Enter expands branches or opens a connection's details. Press `h` for Home; Escape goes back from details/subpages and returns Home from List or Rules. On Home, Escape selects All applications and clears the search. In List, `u` shows all applications without leaving List or clearing the text filter. Press `l` or click List for a full-screen table scoped to the selected tree node; Escape or Home returns to the same tree selection and expansion state. In the list, `g` toggles measured upload/download history. `m` also opens Home. App groups are ordered by retained flow count, with a shared six-cell recent-activity scale.

Connection direction uses `↗` outgoing, `↙` incoming and `↔` for a grouped peer with both. Direction identifies who initiated the connection; reply/download bytes on an outgoing connection keep the outgoing icon. Incoming connections are monitored and allowed. Manual rules and blocklists apply to outgoing connections. Search for `incoming` or `outgoing` to filter by direction, or open details for the local receiving endpoint. The list has a dedicated DIR column. Older saved history is outgoing because earlier providers only recorded that direction.

Use `r` to switch Home/Rules, `/` to search, `b` to block the selected destination globally, `a` to block the selected app or executable service, and `x` to block the destination for its executable. Blocking an application group covers its nested helpers; service and connection scopes remain exact executables. In Rules, Space toggles and `d` removes. `n` adds a domain/IP and `i` imports an HTTPS blocklist URL or local domains/hosts file. Search filters as you type; Enter finishes editing. Domain additions and imports require Enter. Escape closes a prompt or clears the search. `q` exits outside prompts; an activated system filter remains running. The dashboard fits 70×20 and larger terminals; smaller windows display a resize hint. Color follows terminal capabilities and `NO_COLOR`.

In List, click a field above the columns or press `f` to cycle **all / app / service / remote / local / port / type / dir / policy**, then `/` to edit. Filtering happens while typing; `c` clears the text and keeps the selected app/service scope, including after zero results. The **app** field matches the outer app bundle; **service** matches the executable name (or path when the value contains `/`). **remote** matches hostname/IP, **local** matches the local endpoint, and **policy** uses current enabled rules and blocklists rather than the recorded verdict.

With **all** selected, combine terms with spaces, for example `app:"Google Chrome" service:"Google Chrome Helper" remote:example.com type:tcp dir:outgoing policy:block`. Quote values containing spaces. Plain words search across activity fields; terms combine with AND. Direction shortcuts `incoming`/`outgoing` still work. IP-only connections remain searchable by address.

Swift source uses four-space indentation, expanded statements, and one modifier per line on view chains. Presentation decisions belong in named properties/functions rather than long conditions inside `Text`. SwiftFormat 0.64.3 is pinned through `mise.toml`; generated code, dependency checkouts and build output are excluded.

Separate a nested type declaration from the preceding member with a blank line. Enums that begin with cases put the first case directly after the opening brace; other type bodies retain their leading blank line. SwiftFormat preserves this intentional type-body spacing.

Keep qualified types such as `Firewall.Blocklist.Import` intact. When a function signature needs wrapping, wrap its parameter list and retain `) async throws -> Firewall.Blocklist.Import {` together.

```sh
mise install
mise run format        # Apply formatting
mise run format:check  # Check without changing files
mise run test          # Check formatting, then run Swift Testing
```

Launching `nark` without a command opens the live monitor. The executable always connects to the signed filter; in-memory transports live only in test support.

The CLI uses Swift Argument Parser 1.8.2, pinned as an explicit package dependency. Use `nark --help` for commands or `nark help record` (also `nark record --help`) for command-specific options. Arguments are validated before connecting to the filter. Generate shell completions with `nark --generate-completion-script zsh`, replacing `zsh` with `bash` or `fish` as needed.

The installed monitor uses an optimized Release build. `Scripts/package.sh` also defaults to Release; set `NARK_CONFIGURATION=debug` for a debugging bundle. Data-backed lists have explicit viewport heights, so large histories render only visible rows. The full-screen root reads the terminal-size environment directly, and collection columns render as compact styled text. Home materializes disclosed branches and shares one projection for the tree, map and summary. Controls read their own selection writes within an input batch while SwiftLexicon delivers the resulting events.

Run `Scripts/benchmark-navigation.py --size 140x42` against the installed live app for read-only key-to-redraw timings and a rapid-input focus check. Repeat at `--size 200x60` when changing layout; startup timing alone does not measure navigation responsiveness.

`NarkUI` follows SkyUI's semantic component pattern: reusable components accept generated Lexicon concepts, carry their bracketed context, and send inherited control events through the environment's SwiftLexicon `Events`. They have no TCA dependency. `MonitorDashboard` composes them with `nark.ux.monitor` concepts and the monitor store. For example:

```swift
UI.List(tree.visible(navigation), row: nark.ux.monitor.home.tree.row,
        id: \.id, selection: navigation.selection) { concept, row in
    UI.TreeRow(concept, title: row.node.title, depth: row.depth,
               hasChildren: row.node.hasChildren, expanded: row.expanded,
               count: row.node.count, blocked: false,
               activity: row.node.recent, activityMaximum: maximum, width: sidebarWidth-4)
}
```

The list sends the selected row's inherited `event.select`; the session observes it and routes it into the feature. The same component can be reused at another feature path without changing its implementation.

Bindings are projected from owned `@State` through writable key paths. Event-aware value subscripts publish Lexicon changes and selections while preserving the original binding transaction. Do not construct `Binding(get:set:)` adapters. Collection state reads its own writes during an input batch and reconciles authoritative model updates without re-emitting them.

MindFlare's `Searchable` separates editing from submission. Nark follows that pattern with `UI.TextField`: edits emit the inherited `event.change` and filter immediately, while submitting a domain or import is a separate intent. `UI.EventAction` supplies one environment-based delivery/error adapter to SwiftLexicon. `MonitorCommands` owns the experience's semantic keyboard and prompt commands; `DomainList` owns the shared bounded file-import boundary. TCA remains the owner of monitor state and policy requests, and views compose controls rather than perform file imports.

## Application recordings

Start a fresh application recording, use the application normally, then press Ctrl-C to drain the final events and finish the reports:

```sh
/Applications/Nark.app/Contents/MacOS/nark record "/Applications/Google Chrome.app" --output ~/Desktop/chrome-report
/Applications/Nark.app/Contents/MacOS/nark watch --app "/Applications/Google Chrome.app"
```

`record` accepts an app bundle or executable path. It does not launch the target or stop when it quits: recording continues across restarts until you stop the command. Bundle scope includes nested helper executables; shared system helpers outside the bundle cannot be attributed by this path scope. `watch --app` focuses the interactive retained history; it is separate from a fresh recording. Existing blocking controls retain their normal scope (`b` blocks a domain globally; `x` blocks a domain for the selected executable).

The output directory must be new. Without `--output`, Nark creates a timestamped directory under `~/Library/Application Support/Nark/Recordings`. It writes:

- `connections.jsonl`: append-only, timestamped connection observations with executable, direction, remote hostname/IP/port, local endpoint when available, transport, and verdict.
- `report.md`: a readable summary by direction, remote endpoint and executable, with counts and first/last observation times. Incoming records also distinguish the local receiving endpoint.
- `report.json`: the same structured summary and capture status for processing (schema version 2 includes direction).

Files are owner-only. The connection log is flushed on each batch; summaries refresh every five seconds and on a clean stop. Earlier history and existing open connections are not backfilled. The provider keeps a bounded recording buffer independent of global history; gaps are counted and the report is marked incomplete. A provider restart or failure produces a partial report and nonzero exit. If the process is forcibly killed, the last log/checkpoint remains, with no false complete status. Abandoned provider recordings expire after 60 seconds without a read; up to eight can run concurrently.

`record` observes new connections, not individual URLs, decrypted content, or bandwidth. IP-only observations retain the monitor's existing hostname limitations.

## Vocabulary and composition

[`Sources/Vocabulary/nark.lexicon`](Sources/Vocabulary/nark.lexicon) is the source of truth. Lexicon's Swift library build plugin generates the namespace during compilation. Generated Swift is not maintained by hand.

The domains follow the composition patterns in sky-namespace and MindFlare:

| Domain | Concepts |
| --- | --- |
| `nark.system` | Identity, timestamps, lifecycle, persistence |
| `nark.network` | Applications, audit attribution, endpoints, direction, transport, flows |
| `nark.policy` | Match criteria, rules, decisions, policy commands |
| `nark.activity` | Flow + decision + timestamp + count |
| `nark.filter` | Provider composed from policy, flows, activity, lifecycle, persistence |
| `nark.ui` | Reusable control types and application, connection, rule, and collection components |
| `nark.ux` | Feature experiences composed from UI components; monitor selection, search, blocking, and rule editing |

For example, a flow inherits identity, attribution, direction, and transport. An activity record inherits a flow, a decision, and a timestamp. The connection UI component inherits that same concept and the shared control type; the monitor experience composes collections of those components, and a policy match reuses the network application's and endpoint's facets. Composition tests check generated protocol conformance and inherited paths.

`ui` defines reusable component vocabulary; `ux` defines feature experiences. Selection is declared once as `ui.type.control.event.select`, inherited by UI components, and inherited again by the monitor's component instances. Feature routing reads a selected row's identity from the row concept, rather than attaching that identity to a bespoke selection action.

SwiftLexicon owns `Events`, `Event`, `K`, buffering, sending, matching, and observers. Nark defines no alternate bus. The terminal sends vocabulary events, the session's SwiftLexicon observer routes them into TCA, and the runtime emits decision events using composed filter concepts:

```swift
try events.send(Event(nark.ux.monitor.connections.event.move[1]))
try events.send(Event(nark.ux.monitor.home.tree.row[node.id].event.select))
try events.send(Event(nark.ux.monitor.block.destination.event.select))

let observation = runtime.events.on(
    where: { $0.matches(nark.filter.flow.decision.verdict.drop) }
) { event in
    let connection = try? event[nark.filter.flow, as: Firewall.Connection.self]
    // Consume the attributed connection and its policy decision.
}
// Retain observation for the owner's lifetime; cancel on teardown.
```

`Control.Message` is only a versioned XPC transport envelope around SwiftLexicon's Codable `Event.Snapshot`. It translates domain commands at the process boundary. It does not send, observe, or manage subscriptions. XPC authenticates both peers against the expected bundle identifier and signing team before message handling.

Modules:

- `Vocabulary`: generated concepts, re-exports SwiftLexicon.
- `Firewall`: rules, activity, synchronous decisions, bounded state, persistence.
- `Control`: XPC adapter and client.
- `Geography`: bundled IPv4/IPv6 country lookup and Natural Earth country mask; no network lookups.
- `Monitor`: TCA feature and lifecycle-owned SwiftLexicon observation.
- `NarkExtension`: Apple's content-filter callbacks and audit-token attribution.
- `NarkUI`: reusable SwiftTUI components, control bindings, and a single Lexicon event-delivery adapter.
- `Recording`: append-only journals and application report aggregation.
- `NarkApplication`: monitor composition, centralized feature commands, bounded file imports, recording orchestration, and activation.
- `App/Nark` and `App/NarkFilter`: shared eight-line entry points for SwiftPM and Xcode.

## Run a live filter

The host app and system extension must be signed by the same Apple Developer team, with provisioning profiles authorizing the configured identifiers, app group, and Network Extension capability. Ad-hoc signing cannot activate this extension.

Register `com.ollieatkinson.Nark` and `com.ollieatkinson.Nark.Filter` for your team, or adjust the identifiers consistently in `ExtensionConfiguration.swift` and `Scripts/package.sh`. Configure Network Extensions on both IDs, System Extension on the host, and assign both IDs to `group.com.ollieatkinson.Nark`. The app and extension use the same build-versioned Mach service, avoiding endpoint collisions while macOS replaces an older provider. Increment `CURRENT_PROJECT_VERSION` for a new installed build. Packaging validates the profile identifiers, team, expiry, group, and content-filter capabilities. It selects the standard content-filter entitlement for development profiles or the suffixed value for Developer ID profiles.

```sh
export DEVELOPMENT_TEAM=YOURTEAMID
export CODE_SIGN_IDENTITY='Apple Development: Your Name (IDENTITY)'
export APP_PROFILE=/path/to/host.provisionprofile
export EXTENSION_PROFILE=/path/to/filter.provisionprofile
Scripts/package.sh
```

Copy `dist/Nark.app` into `/Applications`, then run the bundled executable:

```sh
/Applications/Nark.app/Contents/MacOS/nark activate
/Applications/Nark.app/Contents/MacOS/nark watch
```

Approve the system extension and network filter when macOS requests it. The provider applies policy independently of terminal lifetime. Rules are persisted atomically in its app-group container. Policy and history are atomic owner-only files in the provider's private app-group directory. Activity retains up to 2,000 aggregate records, checkpoints every five seconds, and restores after restart; an unexpected crash may lose activity since the last checkpoint.

```sh
/Applications/Nark.app/Contents/MacOS/nark block telemetry.example.com
/Applications/Nark.app/Contents/MacOS/nark block-app /usr/bin/curl
/Applications/Nark.app/Contents/MacOS/nark rules
/Applications/Nark.app/Contents/MacOS/nark snapshot
/Applications/Nark.app/Contents/MacOS/nark disable
/Applications/Nark.app/Contents/MacOS/nark deactivate
```

`disable` retains extension and policy; `deactivate` disables and requests extension removal. `clear-history` erases activity, retaining rules. `Scripts/package.sh --unsigned` creates a build artifact only; live monitoring and activation require a signed bundle.

## Current behavior and limits

- Observes new incoming and outgoing socket flows, recording the initiator direction and available local/remote endpoints. Incoming flows are allowed. Blocks new outbound flows by executable or bundle path, domain/IP, or both. Domain rules include subdomains with DNS-label boundary matching. Existing allowed connections are not retroactively terminated.
- Supports named HTTPS/file blocklists, community defaults, independent toggles, source inspection and explicit refresh. Plain domains, hosts files and anchored domain-only Adblock rules are accepted; URL rules, modifiers and exceptions are rejected. Downloads are bounded to 8 MB and refresh failures retain cached policy. Automatic background subscription updates remain future work.
- Uses macOS's supplied hostname when present, bounded TLS ClientHello SNI / plain HTTP Host inspection for otherwise unknown outgoing TCP connections, and QUIC v1/v2 client Initial inspection on UDP ports 443 and 853. QUIC CRYPTO fragments are reassembled across reordered/retransmitted Initials. Buffers, packet counts, wire bytes, concurrent attempts and inspection time are bounded.
- Encrypted ClientHello, unsupported QUIC versions, cached/multiplexed connections, and opaque protocols can remain IP-only. SNI describes the visible handshake name; with real ECH this may be a public cover name, not the hidden destination. Domain rules cannot match a name the filter cannot observe. App/IP rules still apply. QUIC Initial keys are publicly derivable; application traffic and the ECH inner ClientHello are never decrypted. No reverse-DNS guesses.
- Attributes the originating app through `sourceAppAuditToken` and Security.framework. Service rules match exact executable paths. Application-group rules cover paths inside the app bundle, including nested helpers; signed bundle/team identity rules are future work.
- The full-screen List has an optional five-minute mirrored upload/download chart (`g`). Network Extension supplies cumulative byte reports for newly observed incoming and outgoing flows (including their reply traffic). Pre-existing connections are outside these counters. Rates start fresh when the provider restarts; retained flow totals survive restart.
- Home composes an application/service/destination/connection tree with a destination-country map. Groups rank by retained flow count; activity meters share a recent-flow scale. Selection highlights peer countries and markers and scopes the full-screen List. Enter opens a connection's executable, endpoint, counters, country and policy; Escape returns. Rules uses its own full-width page. Search filters as you type.
- Home (also `m`) uses offline country data, scoped to the selected tree node and search. IP Geolocation by [DB-IP](https://db-ip.com), Country Lite October 2026 (CC BY 4.0); map derived from public-domain [Natural Earth](https://www.naturalearthdata.com). Country locations are approximate, particularly for anycast, VPNs and relays. Local/unknown addresses are separate. The app makes no geolocation requests. Dataset attribution and refresh instructions are in `Sources/Geography/Resources/Attribution.txt` and `Scripts/prepare-geography.py`.
- The terminal does not inspect full URL paths or decrypt traffic.
- Activity and policy stay on the Mac. Live blocking has been verified with Little Snitch Mini also active on this Mac.

See [`docs/investigation.md`](docs/investigation.md) for the Binary Ninja evidence and design references.


## Named blocklists

Rules includes presets for [AdAway](https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt) and [Peter Lowe](https://pgl.yoyo.org/adservers/serverlist.php?hostformat=plain&mimetype=plaintext). They start off. Select a list and press Space to enable it (downloading it first if needed), or to disable its cached rules. Enter opens its domains, source, attribution and update time; `/` filters domains as you type, `u` refreshes the source, and Escape returns. Tab moves between lists and manual rules. `i` imports an HTTPS URL or local UTF-8 hosts/domain file as a named list, initially off. Lists apply to outgoing connections from all applications.

Downloads are bounded to 8 MB and use the user process. The provider atomically stores validated lists in its private container; failed or empty updates retain the previous policy. Enabled cached lists continue working without network access. Refreshes are explicit. List domains are indexed separately from manual rules and fetched for inspection only, keeping periodic activity snapshots small. Overlapping lists retain independent on/off state.

```sh
nark blocklists
nark import-blocklist 'https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt'
nark show-blocklist UUID
nark toggle-blocklist UUID
nark update-blocklist UUID
nark remove-blocklist UUID
```

The older `import FILE` command still adds individual manual rules; the Rules-page importer uses named lists.


Press `p` from Rules to browse the community catalog. It includes AdAway, Peter Lowe, 1Hosts Lite, OISD Small, Anudeep, and optional OISD NSFW Small. The picker displays publisher descriptions and source URLs; `c` cycles advertising, tracking, security and explicit categories, and `/` searches the catalog. Enter adds a source or selects one already added. `i` accepts a pasted HTTPS URL or a local file on either page. Added sources remain off until enabled.

Plain domain files, hosts files, and anchored `||domain^` rules are supported. Adblock comments and headers are recognized; URL-path rules, regular expressions, exceptions and rule modifiers are rejected. The importer never silently turns a browser filter into a broader domain rule. The catalog uses 1Hosts' published anchored format and OISD's Small variants; each publisher remains responsible for the feed. Nark stores at most 32 lists, 500,000 domains per list, and 1,000,000 domains combined. Lists are downloaded on addition and refreshed explicitly with `u`.

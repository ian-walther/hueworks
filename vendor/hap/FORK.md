# HueWorks fork of `hap`

Base: [mtrudel/hap](https://github.com/mtrudel/hap) 0.6.0, from the Hex package contents.
Vendored as a path dependency so HueWorks can give accessories, services, and
characteristics explicit, persisted identities. Kept identity-only on purpose; everything
else about the library is used as upstream ships it.

## Changes from 0.6.0

Identity (the reason for the fork):

- `HAP.Accessory` gains an optional `aid`; `HAP.Service` gains an optional `iid`; a
  characteristic may be `{definition, source, iid}`. When any of these is nil the
  upstream positional value is used, so existing accessory trees are unchanged.
- `HAP.Accessory.compile/2` and `HAP.AccessoryServer.compile/1` assign those defaults,
  and reject duplicate accessory IDs and duplicate instance IDs within an accessory
  (services and characteristics share one namespace).
- Lookups go by ID instead of by list position: `HAP.AccessoryServer` finds accessories
  by `aid`, and `HAP.Accessory.find_characteristic/2` finds a characteristic by `iid`
  across services. Requests for an ID that is not published fail with `-70409`.
- `HAP.Characteristic` accepts both tuple shapes; `iid/1` and `value_source/1` added.
- `test/hap/identity_test.exs` covers positional parity, explicit IDs with gaps, routing,
  and duplicate rejection.
- `test/hap/identity_review_test.exs` independently covers repeated characteristic types
  across reordered services, absent IDs, explicit nil entries, shared-namespace
  collisions, subscriptions and notifications, and encrypted HTTP read/write/event
  routing with non-positional IDs.

Backported so the library's own test suite runs on current Bandit (both from upstream
0.7.0, commits e667f54 and 3110913):

- `HAP.HAPSessionHandler.handle_connection/2` delegates to Bandit.
- `HAP.HAPSessionTransport.connection_information/1` delegates to the TCP transport
  (required by Thousand Island 1.5's behaviour).
- `test/hap/hap_session_transport_test.exs` uses 32-byte keys.

HueWorks does not use the library's session handler or transport at runtime; it supplies
its own (`lib/hueworks/homekit/hap_session_*.ex`).

## Running the library's tests

```bash
cd vendor/hap && MIX_ENV=test mix deps.get --only test && mix test
```

`vendor/hap/deps` and `vendor/hap/_build` are ignored by git.

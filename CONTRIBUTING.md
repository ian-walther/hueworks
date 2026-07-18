# Contributing

HueWorks is source-available under the repository license. Contributions are welcome when they preserve the local-appliance boundary and the existing planner/executor architecture.

## Development Setup

```bash
mix setup
mix test
iex -S mix phx.server
```

An empty development database is the normal starting point:

```bash
mix ecto.reset
```

Bridge seeds are optional recovery tooling and must not become a prerequisite for setup.

## Change Expectations

- Reproduce bugs with a failing test before fixing them.
- Run `mix test` after application, test, migration, dependency, or runtime-tooling changes.
- Keep planning documents forward-looking; remove completed work rather than recording progress.
- Keep user documentation synchronized with behavior and known limitations.
- Preserve the runtime/domain split: supervised processes and infrastructure live under `lib/hueworks_app`; domain logic lives under `lib/hueworks`.
- Never include real bridge credentials, tokens, certificate data, addresses, entity names, or database snapshots in fixtures or reports.

Hardware-dependent changes should include deterministic boundary tests plus a clearly described manual smoke test. Do not make the normal automated suite depend on household hardware or network services.

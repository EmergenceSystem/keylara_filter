# keylara_filter
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE.md)

An [em_filter](https://hex.pm/packages/em_filter) agent that exposes the [KeyLARA](https://hex.pm/packages/keylara) cryptographic entropy API as an [Emergence](https://github.com/EmergenceSystem/em_disco) agent.

KeyLARA provides cryptographically secure entropy sourced from the ALARA distributed pool, mixed with SHA3-256 before delivery.

## Actions

| Action | Parameters | Default | Returns |
|---|---|---|---|
| `get_entropy_bytes` | `n` | 32 | base64-encoded entropy bytes |
| `get_version` | — | — | KeyLARA version string |
| `get_network_pid` | — | — | ALARA supervisor PID or error |
| `start` | — | — | start KeyLARA and its dependencies |
| `stop` | — | — | stop KeyLARA |

Default action when no `action` field is present: `get_entropy_bytes` with `n=32`.

## Usage

**Via curl (direct to em_disco):**

```bash
# 32 entropy bytes (default)
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "keylara", "capabilities": ["keylara"]}'

# 64 entropy bytes
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "{\"action\":\"get_entropy_bytes\",\"n\":64}", "capabilities": ["keylara"]}'

# Version
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "{\"action\":\"get_version\"}", "capabilities": ["keylara"]}'

# ALARA supervisor PID
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "{\"action\":\"get_network_pid\"}", "capabilities": ["keylara"]}'
```

**Via Erlang shell:**

```erlang
emquest_cli:query(<<"keylara">>).
emquest_cli:query(<<"{\"action\":\"get_entropy_bytes\",\"n\":128}">>).
emquest_cli:query(<<"{\"action\":\"get_version\"}">>).
```

## Installation

```bash
git clone https://github.com/EmergenceSystem/keylara_filter.git
cd keylara_filter
rebar3 shell --apps keylara_filter
```

Requires `em_disco` running on `localhost:8080` (configured in `emergence.conf`).

## Capabilities

`search`, `query`, `keylara`, `entropy`, `crypto`, `random`, `erlang`

## License

Apache 2.0 — see [LICENSE.md](LICENSE.md).

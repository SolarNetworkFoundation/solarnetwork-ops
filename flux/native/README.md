# SolarFlux VerneMQ — native webhook deployment

Configuration for a **stand-alone (non-clustered) VerneMQ 2.1.1** broker running alongside the
GraalVM native-image build of `solarflux-vernemq-webhook`, sized for a **1 GB instance**
(`t4g.micro`, ~928 MB usable).

Most of the settings in this directory exist to make VerneMQ fit a 1 GB box. VerneMQ ships
LevelDB defaults inherited from Riak that assume 32 GB+ of RAM; left alone they will OOM this
instance roughly monthly. See [Why the LevelDB settings are here](#why-the-leveldb-settings-are-here)
before changing any of them.

## Files

| File | Deploys to |
| --- | --- |
| `vernemq-conf-211.patch` | patch against the stock VerneMQ 2.1.1 `/etc/vernemq/vernemq.conf` |
| `solarflux.conf` | SolarFlux-specific additions to `/etc/vernemq/vernemq.conf` |
| `fluxhook-native.service` | the `fluxhook.service` unit (currently `/usr/lib/systemd/system/fluxhook.service` on `solarflux-a`) |
| `application-production.yml` | `/var/lib/fluxhook/application-production.yml` |
| `logging-production.xml` | `/var/lib/fluxhook/` (see `logging.config` in the YAML) |

The VerneMQ systemd resource limits live one level up, in `../vernemq-override.service`.

## Memory budget

Steady-state figures observed on the production instance, 2026-09-28:

| | `VmRSS` | of which anon |
| --- | --- | --- |
| `beam.smp` (VerneMQ) | ~215 MB | ~156 MB |
| `solarflux-webhook` (native) | ~185 MB | ~80 MB |
| OS + page cache | remainder | — |
| **Available** | **~476 MB of 928 MB** | |

The webhook's RSS is roughly half file-backed (the native binary's own text and rodata), which
is reclaimable and should not be read as heap pressure.

## Why the LevelDB settings are here

> :warning: Do not "clean up" `leveldb.write_buffer_size_min` / `_max` from `solarflux.conf`.
> They are not cosmetic and they are not the defaults — they are the fix for a recurring
> production outage.

### Symptoms

Between roughly 2025-09 and 2026-09 the broker was killed by the kernel OOM killer about once a
month. The pattern each time:

- MQTT message flow was flat — no monthly spike, no growth in sessions.
- `beam.smp` anonymous RSS climbed steadily, ~20 MB/day, from ~120 MB after a restart to
  400+ MB over two to three weeks.
- EBS read ops ramped smoothly upward over the days before the kill.
- Restarting VerneMQ returned everything to normal, for another month.

### Root cause

VerneMQ gives **every LevelDB instance its own write buffer, randomly sized between
`leveldb.write_buffer_size_min` and `_max`** — and the built-in defaults for those are Riak's
**30 MB and 60 MB** ([`vmq_swc_db_leveldb.erl:270`](https://github.com/vernemq/vernemq/blob/2.1.1/apps/vmq_swc/src/vmq_swc_db_leveldb.erl#L270)).

A stand-alone broker opens far more LevelDB instances than is obvious:

| Store | Setting | Default | Instances |
| --- | --- | --- | --- |
| `swc_meta` | `vmq_swc.swc_groups` | 10 | 10 |
| `swc_dkm` | one DB per SWC group | — | 10 |
| `msgstore` | `vmq_generic_msg_store.nr_of_buckets` | 12 | 12 |
| | | | **32** |

32 instances × ~45 MB average = **~1.4 GB of potential memtable on a 928 MB box.** The broker
was configured to exceed physical RAM by 50%, regardless of load.

At the low write rate of this deployment a 45 MB buffer takes *weeks* to fill, which is exactly
why the failure was monthly rather than immediate, and why a restart always "fixed" it — restarting
empties every memtable.

`leveldb.maximum_memory` does **not** bound this. It maps to eleveldb's `total_leveldb_mem`, which
sizes the flexcache (block cache + file metadata cache) only. Write buffers are allocated per
database independently of it.

### Evidence

Measured immediately before the fix, at 16 days uptime:

```
beam.smp RssAnon                          416 MiB
erlang:memory(total)                       71 MiB
                                        ---------
unaccounted (eleveldb NIF allocations)    345 MiB

sum of the 10 open swc_meta write-ahead logs, none yet flushed:
  meta1 79 MB, meta8 50, meta5 39, meta9 37, meta4 30,
  meta7 29, meta3 28, meta6 26, meta10 26, meta2 25   = 352 MiB
```

The unaccounted RSS matched the un-flushed WAL total to within a few percent. For context, the
whole dataset those buffers were serving is 37 router subscriptions and 19 retained messages.

The EBS read-op ramp was a **symptom, not a cause**: growing anonymous memory evicted the page
cache (`buff/cache` fell 391 → 173 MB over a week), after which every LevelDB read became a real
EBS read.

### Result

With `write_buffer_size_min = 2MB` / `max = 4MB`, at the same 16-day uptime:

| | Before | After |
| --- | --- | --- |
| `beam.smp` `RssAnon` | 416 MiB | **156 MiB** |
| Non-Erlang portion | 346 MiB | 85 MiB |
| Growth rate | +21 MB/day | +2.8 MB/day |
| Available memory | 242 MB | 476 MB |
| Swap used | 50 MB, rising | 21 MB, flat 16 days |

Per-database write buffers came out between 2.40 and 3.92 MB, 29.6 MB across the ten `swc_meta`
instances — versus 352 MB before.

**No instance resize was needed.** This was a configuration defect, not a capacity problem.

## Diagnosing a memory regression

The single most useful measurement. Erlang cannot see memory allocated by the eleveldb NIF, so
the **gap** between process RSS and the VM's own accounting is the LevelDB footprint:

```sh
grep RssAnon /proc/$(pidof beam.smp)/status
echo 'erlang:memory(total).' | /usr/lib/vernemq/erts-*/bin/erl_call \
  -name VerneMQ@127.0.0.1 \
  -c "$(grep -oP '^distributed_cookie\s*=\s*\K\S+' /etc/vernemq/vernemq.conf)" -e
```

| Gap | Reading |
| --- | --- |
| under ~100 MB | healthy |
| 150–250 MB | block cache warming toward `leveldb.maximum_memory`; expect it to asymptote |
| 300 MB+ and climbing daily | write buffers are oversized again — check the settings are live |

`erlang:memory(total)` has been stable at 71–74 MB throughout, before and after the incident. If
*that* number is what grew, the problem is in Erlang (processes, ETS, binaries) and LevelDB is not
the culprit — break it down with `erlang:memory().`

Confirm the WALs are actually cycling. They should stay in the single-digit MB range and be
replaced regularly, not grow monotonically for weeks:

```sh
ls -l /var/lib/vernemq/swc_meta/*/*.log
```

## Inspecting the webhook heap

There is no actuator endpoint in this build (`spring-boot-starter-actuator` is not a dependency, so
`/actuator/*` returns 404), and `jcmd` / `jmap` do not work against a native image. GC logging is
the only window in. It is deliberately **not** enabled by default — add it temporarily when
investigating, then remove it.

A drop-in cannot *append* to `ExecStart`, and a second `ExecStart=` on a `Type=simple` unit is an
error. Clear it first, then restate the whole command:

```sh
systemctl edit fluxhook
```

```ini
[Service]
ExecStart=
ExecStart=/var/lib/fluxhook/solarflux-webhook -Xms48m -Xmx160m -XX:+ExitOnOutOfMemoryError -XX:+PrintGC -XX:+VerboseGC -Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom -Djava.net.preferIPv4Stack=true -Dserver.contextPath=/ -Dserver.port=8280
```

```sh
systemctl daemon-reload && systemctl restart fluxhook
journalctl -u fluxhook -f | grep -i gc
```

Reading it: the unit passes `-Xms48m` specifically to override the `-R:MinHeapSize=128m` floor baked
into the image at build time — without it the heap cannot drop below 128 MB and RSS growth tells you
nothing. With it, a heap settling near 48 MB after collection is healthy; one climbing steadily
toward the 160 MB ceiling is a genuine leak, and the unbounded `Actor` cache (a JCache `MutableConfiguration`
with a 900 s TTL and no size limit, backed by Ehcache's unbounded heap tier) is the first suspect.

Object-level detail requires rebuilding the image with `--enable-monitoring=heapdump`.

## Verifying the LevelDB settings are live

Four layers, cheapest first. The first two reflect what is **on disk**; the last two reflect what
the **running broker** actually holds.

```sh
# 1. cuttlefish parses it (reads the current file, not necessarily the running config)
vernemq config describe leveldb.write_buffer_size_max

# 2. the running node loaded it — check the generated config postdates the process start
ps -o lstart= -p $(pidof beam.smp)
grep -o 'write_buffer_size_[a-z]*,[0-9]*' \
  $(ls -t /var/lib/vernemq/generated.configs/app.*.config | head -1)

# 3. live application environment
echo 'application:get_all_env(eleveldb).' | /usr/lib/vernemq/erts-*/bin/erl_call \
  -name VerneMQ@127.0.0.1 \
  -c "$(grep -oP '^distributed_cookie\s*=\s*\K\S+' /etc/vernemq/vernemq.conf)" -e

# 4. the size each database actually chose (randomised per DB at open)
echo '[{element(4,C), proplists:get_value(write_buffer_size, element(4, sys:get_state(element(4,C))))} || {_,C} <- ets:tab2list(vmq_swc_group_config)].' \
  | /usr/lib/vernemq/erts-*/bin/erl_call -name VerneMQ@127.0.0.1 \
  -c "$(grep -oP '^distributed_cookie\s*=\s*\K\S+' /etc/vernemq/vernemq.conf)" -e
```

Step 4 is the one that matters — expect ten values in the 2–4 MB range. Use `element(5,C)` for the
DKM databases. The `element/2` offsets are the VerneMQ 2.1.1 record layouts (`#swc_config.db` is 4,
`#state.open_opts` is 4); if the output looks wrong, print `sys:get_state(vmq_swc_db_meta1)` raw.

The twelve `msgstore` buckets are not in that ETS table but read the same `eleveldb` app env, so
step 3 covers them.

## cgroup limits

Both units are bounded so that a memory regression degrades one service instead of letting the
kernel pick a victim system-wide. `OOMScoreAdjust` biases the global OOM killer towards the
webhook (cheap to restart, ~100 ms for a native image) and away from the broker.

Check for throttling and kills:

```sh
systemctl show -p MemoryHigh -p MemoryMax -p OOMScoreAdjust vernemq fluxhook
grep . /sys/fs/cgroup/system.slice/{vernemq,fluxhook}.service/memory.events
```

`max`, `oom` and `oom_kill` should all be 0. A non-zero, *advancing* `high` count means that
service is being throttled into direct reclaim — set `MemoryHigh` comfortably above the normal
working set, or it fires continuously and tells you nothing.

Quantify whether throttling actually costs anything before acting on it — `memory.events` counts
occurrences, `memory.pressure` reports stall time in microseconds:

```sh
cat /sys/fs/cgroup/system.slice/fluxhook.service/memory.pressure
```

> :bulb: cgroup v2 charges page cache to the unit, so `memory.current` reads well above `VmRSS`.
> That is expected and reclaimable.

## Healthy baselines

As of 2026-09-28, ~16 days uptime, ~75–100 concurrent MQTT sessions:

| Metric | Value |
| --- | --- |
| `beam.smp` `RssAnon` | ~156 MB |
| `erlang:memory(total)` | ~72 MB |
| Erlang process count | ~570 |
| `gauge.queue_processes` | ~60 |
| `gauge.router_subscriptions` | ~37 |
| `gauge.retain_messages` | 19 |
| `solarflux-webhook` `VmRSS` | ~185 MB |
| Available memory | ~476 MB of 928 MB |
| Swap used | 21 MB, not growing |
| `swc_meta` on disk | ~143 MB |
| `swc_dkm` on disk | ~114 MB |
| `msgstore` on disk | <1 MB |

No persistent sessions and effectively no retained-message usage, so the `msgstore` stays
near-empty. The `swc_meta` / `swc_dkm` sizes are driven by session churn, not by subscription
count — see [Open items](#open-items).

## Gotchas

**`systemctl edit` replaces the whole file.** It is not a merge. Re-editing a drop-in to change one
value will silently drop every other directive unless you keep them. Always confirm with
`systemctl cat <unit>` afterwards.

**`daemon-reload` does not reliably push memory limits to a running cgroup.** After editing limits,
either restart the unit or use `systemctl set-property` — and verify against
`/sys/fs/cgroup/system.slice/<unit>.service/memory.{high,max}`, not `systemctl show`.
`systemctl set-property` writes its own drop-in under `/etc/systemd/system.control/` which then
shadows the one in `/etc/systemd/system/`, so prefer a restart where a restart is cheap.

**`OOMScoreAdjust` applies at process start.** A running process keeps the value it was given, so a
unit-file change has no effect until the next restart.

**Do not restart VerneMQ to apply cosmetic changes while investigating memory.** A restart empties
every memtable and resets the measurement you are taking; uptime *is* the experiment. The webhook
can be restarted freely.

**`leveldb.maximum_memory` must stay explicit.** `leveldb.maximum_memory.percent` remains present
and defaults to 70 — if the explicit byte value is ever dropped during a config cleanup or a
package upgrade rewrites `vernemq.conf`, the budget silently becomes ~650 MB on this instance.

**`vmq_swc.swc_groups` cannot be reduced in place.** Lowering it (to cut the number of LevelDB
instances further) re-shards the metadata and orphans the existing `swc_meta` / `swc_dkm` data. It
requires stopping VerneMQ and moving those directories aside, which loses retained messages;
subscriptions rebuild on reconnect. Not currently done — the write-buffer fix was sufficient.

## Other deployments

Two sibling configs previously specified the stock 30/60 MB write buffers and have been brought in
line with the values here:

- `../vernemq-conf.patch` — the older, non-native SolarFlux deployment
- `../../queue/vernemq/vernemq-conf.patch` — SolarQueue's VerneMQ

> :warning: 2 MB / 4 MB is sized for *this* deployment: a 1 GB host with a low metadata write rate.
> The tradeoff is more frequent memtable flushes and compaction, which is free here and may not be
> on a busier broker. SolarQueue runs VerneMQ 1.12.1, which defaults to the plumtree metadata plugin
> rather than SWC — so its exposure is the 12 `msgstore` buckets (up to ~720 MB) rather than 32
> instances, and its host may have room the SolarFlux box does not. Re-check the value against that
> host's RAM and write rate before the next deploy there.

## Open items

- **Webhook heap growth is still uncharacterised.** Before the `-Xmx` reduction the webhook's
  anonymous RSS grew ~5 MB/day with no observed plateau. That is consistent with a real leak *and*
  with the collector simply walking up to the 128 MB floor baked into the image — the two have
  opposite conclusions and RSS alone cannot separate them. `-Xms48m` (in the unit) removes the
  floor; GC logging (see [Inspecting the webhook heap](#inspecting-the-webhook-heap)) settles the
  rest, on demand. `solarflux-a` is still running the pre-`-Xms` command line until the unit is
  redeployed.
- **Reconnect churn.** ~8,000 `queue_setup` events per day for 75–100 sessions means clients are
  reconnecting roughly every 16 minutes, which generated 1.87M SWC metadata writes over 16 days and
  is why 257 MB of LevelDB data describes 37 subscriptions. Client-side issue; harmless to memory
  now, but pointless work.
- **Residual growth.** +2.8 MB/day of non-Erlang memory, believed to be block cache warming toward
  the 100 MB `leveldb.maximum_memory` budget and therefore self-limiting. If it is still climbing
  linearly past ~250 MB, `leveldb.block_cache_threshold` (32 MB, *per database*) is the next knob.
- **Deployment mechanism for `solarflux.conf` is not recorded here.**
- **`fluxhook.service` limits live in two places.** The values now agree — 260M/320M here and on
  `solarflux-a` — but the server carries them in a drop-in
  (`/etc/systemd/system/fluxhook.service.d/override.conf`) over the packaged unit, whereas this repo
  keeps them in the unit itself. Prefer the unit, given the `systemctl edit` hazard noted above, and
  drop the override when the unit is next redeployed.

  For the record on why they changed: `MemoryHigh=180M` sat *below* the process's ~185 MB working
  set once the binary grew, throttling it into direct reclaim continuously — 2236 events, though
  only ~0.2 s of cumulative stall across the cgroup's lifetime, i.e. real but negligible. The
  argument for raising it was that a soft limit which fires constantly conveys no information, not
  that it was costing measurable latency.

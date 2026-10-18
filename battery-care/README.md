# omarchy-battery-care

Keeps the battery at the protective charge threshold instead of leaving it parked
above it.

## The problem it solves

TLP charge thresholds are a hysteresis loop, not a fill-to level:

```
level < START   -> charging allowed
level >= STOP   -> charging stopped
START..STOP     -> nothing happens either way
```

The embedded controller only ever *stops* charging; it never discharges. So a pack
that was charged above STOP stays there. Charging to 100% once (the battery panel's
**Full** preset runs `tlp setcharge 95 100`) and then choosing **Protect** again
writes 75/80 back — but the electrons are already in the pack, and the machine sits
at 99% on AC indefinitely, which is exactly the state 75/80 exists to avoid.
Self-discharge is ~1–3 %/month, so waiting is not a plan. TLP cannot help: its own
FAQ states the thresholds "do not exercise any control over the discharging of the
battery".

This service does the one thing TLP will not: on AC, when STOP is in a protective
band and the charge level is above it, it enables the pack's own `force-discharge`
until the level falls back to STOP.

## Why it is a resident loop, not a one-shot

**`force-discharge` does not stop at `charge_control_end_threshold`.** The kernel
documents the start/stop thresholds as charge-scoped ("above which charging will
stop") and ties "respect thresholds" to the `auto` behaviour only. On ThinkPads the
battery hook calls ACPI `BDSS` on the HKEY handle with no threshold operand and
never monitors the result. So while `force-discharge` is selected, *the service is
the brake* — with nothing to stop it, an armed discharge would run toward 0 % while
on AC.

That is why the brake is deliberately duplicated:

| # | Brake | Covers |
|---|-------|--------|
| 1 | loop re-reads sysfs every tick (5 s while discharging) | normal stop, within a tick |
| 2 | `EXIT`/`INT`/`TERM` traps write `auto` | normal stop, `^C`, `systemctl stop` |
| 3 | `ExecStopPost=… --release` | stop/restart even if the loop died badly |
| 4 | `omarchy-battery-care-sleep.service` | suspend — the loop cannot run while asleep |
| 5 | `Restart=always` | a crashed loop resumes correcting within 5 s |
| 6 | UPower critical-battery action | last-resort OS floor |

Known gap, stated rather than hidden: **`SIGKILL` beats the traps**, and
`ExecStopPost` was measured on this machine not to run after one. A SIGKILLed
daemon can therefore leave the discharge armed — brakes 3 and 4 are what clean that
up, and the loop's stateless re-derivation means a restart repairs it within a tick.
The contract test asserts this gap explicitly rather than pretending it is closed.

A simpler one-shot was rejected for the same reason: `tlp discharge` blocks and
polls internally but only ever traps `SIGINT`, so a `SIGKILL` would leave
`force-discharge` armed with nothing left to end it.

## What it refuses to do

`charge_behaviour` is only touched while STOP is in the protective band, by default
**50–80 %**:

- **Above the band** — the panel's **Full** preset is 95–100, so choosing Full both
  cancels an in-flight discharge (charging can then actually start) and keeps this
  service out of the way until **Protect** is chosen again.
- **Below the band** — a `START=0 STOP=0` pair is a real convention meaning "no
  start threshold"; without the floor it would read as "discharge to 0 %".
- **On battery** — force-discharge is pointless and unwanted; an armed discharge is
  disarmed instead.

## Usage

```
sudo ./install.sh              install and start
sudo ./install.sh --dry-run    say what it would do
sudo ./install.sh --remove     stop, disarm, remove everything
```

```
omarchy-battery-care --status     print the decision, change nothing
omarchy-battery-care --release    disarm unconditionally
omarchy-battery-care              reconcile once and exit
omarchy-battery-care --daemon     resident loop (what the unit runs)
```

Tuning is by environment, set in the unit:

| Variable | Default | Meaning |
|---|---|---|
| `OMARCHY_BATTERY_PROTECT_MIN_STOP` | 50 | lower bound of the protective band |
| `OMARCHY_BATTERY_PROTECT_MAX_STOP` | 80 | upper bound of the protective band |
| `OMARCHY_BATTERY_IDLE_TICK` | 30 | poll seconds while idle |
| `OMARCHY_BATTERY_ACTIVE_TICK` | 5 | poll seconds while discharging |

State to check:

```
omarchy-battery-care --status
journalctl -u omarchy-battery-care -f
cat /sys/class/power_supply/BAT0/charge_behaviour
```

Pause without uninstalling: `touch /etc/omarchy-battery-care-off && systemctl
restart omarchy-battery-care` (the unit carries a matching `ConditionPathExists=`).

## Layout

```
/usr/local/sbin/omarchy-battery-care                    the script (root-owned copy)
/etc/systemd/system/omarchy-battery-care.service        the loop
/etc/systemd/system/omarchy-battery-care-sleep.service  disarm before sleep
```

The installed script is a real root-owned copy, never a symlink into the repository
or `~/bin` — a root-run path a normal user could rewrite is a privilege-escalation
hole. Re-run `install.sh` after changing this directory.

No polkit rule or sudoers entry is involved: the service runs as root from systemd,
and the battery panel's existing rule for `/usr/bin/tlp` already covers the
threshold writes it reacts to.

## Testing

```
./tests/test-battery-care.sh
```

47 checks against a fake sysfs tree: decisions, idempotence, every refusal case,
`--release`, the daemon's arm/disarm cycle at the threshold, and the `SIGKILL` gap.
Nothing touches a real battery or `/sys`.

## Hardware support

Needs a charge threshold plus the kernel's `force-discharge` capability
(`charge_behaviour`, kernel ≥ 5.17). Without them the service conditions itself out
and `--status` reports "capability no".

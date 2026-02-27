#!/usr/bin/env python3
"""
LiveMon - Raspberry Pi 5 System Monitor

Multi-panel curses TUI with JSONL logging.

Key goals:
- Collect CPU/RAM/Storage/Temps/Power + throttle state.
- Keep working even if some sensors/commands are unavailable.
"""

from __future__ import annotations

import curses
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, Iterable, List, Optional, Tuple

# --- CONFIGURATION ---
PMIC_EFFICIENCY_BASE = 0.88
UNMONITORED_OFFSET_W = 0.8

DEFAULT_REFRESH_S = 1.0
HISTORY_SECONDS = 120

# --- THRESHOLDS ---
VOLT_WARN_LOW = 4.85
VOLT_CRIT_LOW = 4.75
TEMP_WARN = 70.0
TEMP_CRIT = 80.0
CPU_WARN = 80.0
MEM_WARN = 85.0
DISK_WARN = 90.0

# --- THROTTLE CODES ---
THROTTLE_CODES = {
    0:  ("Under-voltage detected", "CRITICAL"),
    1:  ("ARM Frequency Capped",   "WARNING"),
    2:  ("Currently Throttled",    "WARNING"),
    3:  ("Soft Temp Limit",        "WARNING"),
    16: ("Past Under-voltage",     "HISTORY"),
    17: ("Past Freq Cap",          "HISTORY"),
    18: ("Past Throttling",        "HISTORY"),
    19: ("Past Temp Limit",        "HISTORY"),
}


def _clamp(val: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, val))


def _fmt_bytes(num: float) -> str:
    step = 1024.0
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    v = float(num)
    for u in units:
        if abs(v) < step:
            return f"{v:,.1f}{u}" if u != "B" else f"{v:,.0f}{u}"
        v /= step
    return f"{v:,.1f}PiB"


def _fmt_percent(p: float) -> str:
    return f"{p:5.1f}%"


def _render_bar(percent: float, width: int) -> str:
    width = max(1, width)
    filled = int(round(width * _clamp(percent, 0.0, 100.0) / 100.0))
    return "█" * filled + " " * (width - filled)


def _sparkline(values: Iterable[float], width: int, max_val: float) -> str:
    vals = list(values)
    if width <= 0:
        return ""
    if not vals:
        return " " * width

    chars = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    if len(vals) > width:
        step = len(vals) / width
        sampled = [vals[int(i * step)] for i in range(width)]
    else:
        sampled = vals + [vals[-1]] * (width - len(vals))

    out = []
    for v in sampled[:width]:
        n = 0.0 if max_val <= 0 else _clamp(float(v) / float(max_val), 0.0, 1.0)
        out.append(chars[int(round(n * (len(chars) - 1)))])
    return "".join(out)


def _safe_addstr(win: "curses.window", y: int, x: int, s: str, attr: int = 0) -> None:
    try:
        h, w = win.getmaxyx()
        if y < 0 or y >= h or x >= w:
            return
        if x < 0:
            s = s[-x:]
            x = 0
        if not s:
            return
        win.addnstr(y, x, s, w - x - 1, attr)
    except curses.error:
        return


def _init_colors() -> None:
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)
    curses.init_pair(2, curses.COLOR_YELLOW, -1)
    curses.init_pair(3, curses.COLOR_RED, -1)
    curses.init_pair(4, curses.COLOR_CYAN, -1)
    curses.init_pair(5, curses.COLOR_MAGENTA, -1)
    curses.init_pair(6, curses.COLOR_WHITE, -1)


def _color_by_percent(p: float, warn: float, crit: float) -> int:
    if p >= crit:
        return curses.color_pair(3)
    if p >= warn:
        return curses.color_pair(2)
    return curses.color_pair(1)


def _color_by_temp(t: float) -> int:
    if t >= TEMP_CRIT:
        return curses.color_pair(3)
    if t >= TEMP_WARN:
        return curses.color_pair(2)
    return curses.color_pair(1)


def _color_by_voltage(v: float) -> int:
    if v <= VOLT_CRIT_LOW:
        return curses.color_pair(3)
    if v <= VOLT_WARN_LOW:
        return curses.color_pair(2)
    return curses.color_pair(1)


def ensure_root_or_reexec(argv: List[str]) -> None:
    if os.geteuid() == 0:
        return
    if "--no-sudo" in argv:
        return

    sudo = shutil.which("sudo")
    if not sudo:
        print("livemon: needs root for vcgencmd/PMIC. Re-run with sudo or use --no-sudo.")
        raise SystemExit(1)

    script_path = os.path.realpath(__file__)
    os.execvp(sudo, [sudo, "-E", sys.executable, script_path, *argv[1:]])


@dataclass
class DiskUsage:
    mount: str
    total_b: int
    used_b: int
    free_b: int

    @property
    def percent(self) -> float:
        return (self.used_b / self.total_b * 100.0) if self.total_b > 0 else 0.0


class CommandRunner:
    def __init__(self) -> None:
        self._vcgencmd = shutil.which("vcgencmd")

    @property
    def has_vcgencmd(self) -> bool:
        return bool(self._vcgencmd)

    def run(self, args: List[str], timeout_s: float = 1.5) -> str:
        try:
            result = subprocess.run(
                args,
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
            return (result.stdout or "").strip()
        except Exception:
            return ""

    def vcgencmd(self, *args: str) -> str:
        if not self._vcgencmd:
            return ""
        return self.run([self._vcgencmd, *args], timeout_s=1.8)


class MetricsCollector:
    def __init__(self, history_len: int) -> None:
        self.runner = CommandRunner()
        self._last_cpu_times: Optional[Dict[str, Tuple[int, int]]] = None
        self.cpu_avg_hist = deque(maxlen=history_len)
        self.cpu0_temp_hist = deque(maxlen=history_len)
        self.power_hist = deque(maxlen=history_len)

    def _read_proc_stat(self) -> Dict[str, Tuple[int, int]]:
        out: Dict[str, Tuple[int, int]] = {}
        try:
            with open("/proc/stat", "r", encoding="utf-8") as f:
                for line in f:
                    if not line.startswith("cpu"):
                        continue
                    parts = line.split()
                    name = parts[0]
                    if name == "cpu":
                        continue
                    times = [int(x) for x in parts[1:8]]  # user nice system idle iowait irq softirq
                    idle = times[3] + times[4]
                    total = sum(times)
                    out[name] = (idle, total)
        except Exception:
            return {}
        return out

    def cpu_usage(self) -> Dict[str, float]:
        current = self._read_proc_stat()
        if not current:
            return {}
        if self._last_cpu_times is None:
            self._last_cpu_times = current
            return {k: 0.0 for k in current.keys()}

        usage: Dict[str, float] = {}
        for cpu, (idle, total) in current.items():
            prev = self._last_cpu_times.get(cpu)
            if not prev:
                continue
            prev_idle, prev_total = prev
            d_total = total - prev_total
            d_idle = idle - prev_idle
            if d_total <= 0:
                usage[cpu] = 0.0
            else:
                usage[cpu] = _clamp(100.0 * (d_total - d_idle) / d_total, 0.0, 100.0)
        self._last_cpu_times = current
        return usage

    def load_avg(self) -> Tuple[float, float, float]:
        try:
            with open("/proc/loadavg", "r", encoding="utf-8") as f:
                a, b, c = f.read().split()[:3]
            return float(a), float(b), float(c)
        except Exception:
            return 0.0, 0.0, 0.0

    def uptime_s(self) -> float:
        try:
            with open("/proc/uptime", "r", encoding="utf-8") as f:
                return float(f.read().split()[0])
        except Exception:
            return 0.0

    def uptime_str(self) -> str:
        s = int(self.uptime_s())
        days, rem = divmod(s, 86400)
        hours, rem = divmod(rem, 3600)
        mins, _ = divmod(rem, 60)
        if days:
            return f"{days}d {hours}h {mins}m"
        if hours:
            return f"{hours}h {mins}m"
        return f"{mins}m"

    def mem(self) -> Dict[str, float]:
        info: Dict[str, int] = {}
        try:
            with open("/proc/meminfo", "r", encoding="utf-8") as f:
                for line in f:
                    if ":" not in line:
                        continue
                    k, v = line.split(":", 1)
                    parts = v.strip().split()
                    if not parts:
                        continue
                    info[k.strip()] = int(parts[0])  # kB
        except Exception:
            return {
                "ram_total_b": 0,
                "ram_used_b": 0,
                "ram_percent": 0.0,
                "swap_total_b": 0,
                "swap_used_b": 0,
                "swap_percent": 0.0,
            }

        mem_total = info.get("MemTotal", 0) * 1024
        mem_avail = info.get("MemAvailable", info.get("MemFree", 0)) * 1024
        mem_used = max(0, mem_total - mem_avail)
        ram_percent = (mem_used / mem_total * 100.0) if mem_total else 0.0

        swap_total = info.get("SwapTotal", 0) * 1024
        swap_free = info.get("SwapFree", 0) * 1024
        swap_used = max(0, swap_total - swap_free)
        swap_percent = (swap_used / swap_total * 100.0) if swap_total else 0.0

        return {
            "ram_total_b": float(mem_total),
            "ram_used_b": float(mem_used),
            "ram_percent": float(ram_percent),
            "swap_total_b": float(swap_total),
            "swap_used_b": float(swap_used),
            "swap_percent": float(swap_percent),
        }

    def disk_usage(self, mounts: Optional[List[str]] = None) -> List[DiskUsage]:
        if mounts is None:
            mounts = ["/", "/boot", "/boot/firmware"]
        seen = set()
        usages: List[DiskUsage] = []
        for m in mounts:
            if not m or m in seen:
                continue
            seen.add(m)
            if not os.path.exists(m):
                continue
            try:
                du = shutil.disk_usage(m)
                usages.append(DiskUsage(mount=m, total_b=du.total, used_b=du.used, free_b=du.free))
            except Exception:
                continue
        return usages

    def cpu_freq_mhz(self) -> float:
        # Prefer kernel-provided frequency
        path = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
        try:
            with open(path, "r", encoding="utf-8") as f:
                khz = int(f.read().strip())
            return khz / 1000.0
        except Exception:
            pass
        raw = self.runner.vcgencmd("measure_clock", "arm")
        # frequency(48)=2400000000
        try:
            hz = int(raw.split("=")[1])
            return hz / 1_000_000.0
        except Exception:
            return 0.0

    def throttled_hex(self) -> int:
        raw = self.runner.vcgencmd("get_throttled")
        try:
            return int(raw.split("=")[1], 16)
        except Exception:
            return 0

    def temps_c(self) -> Dict[str, float]:
        temps: Dict[str, float] = {}

        raw = self.runner.vcgencmd("measure_temp")
        # temp=44.6'C
        try:
            if raw:
                temps["CPU"] = float(raw.replace("temp=", "").replace("'C", ""))
        except Exception:
            pass

        # thermal zones
        try:
            base = "/sys/class/thermal"
            for d in os.listdir(base):
                if not d.startswith("thermal_zone"):
                    continue
                t_path = os.path.join(base, d, "temp")
                ty_path = os.path.join(base, d, "type")
                try:
                    with open(ty_path, "r", encoding="utf-8") as f:
                        t_type = f.read().strip() or d
                    with open(t_path, "r", encoding="utf-8") as f:
                        val = f.read().strip()
                    if not val:
                        continue
                    t = float(val) / 1000.0 if len(val) > 3 else float(val)
                    key = t_type.strip()
                    key = key.replace("-thermal", "").replace("thermal", "").strip() or d
                    key = key[:18]
                    if key.lower() == "cpu" and "CPU" in temps:
                        continue
                    temps.setdefault(key, t)
                except Exception:
                    continue
        except Exception:
            pass

        # hwmon temps
        try:
            base = "/sys/class/hwmon"
            for hw in os.listdir(base):
                hw_path = os.path.join(base, hw)
                name = hw
                try:
                    with open(os.path.join(hw_path, "name"), "r", encoding="utf-8") as f:
                        name = f.read().strip() or name
                except Exception:
                    pass
                for fn in os.listdir(hw_path):
                    if not fn.startswith("temp") or not fn.endswith("_input"):
                        continue
                    idx = fn[4: fn.find("_input")]
                    label = None
                    try:
                        with open(os.path.join(hw_path, f"temp{idx}_label"), "r", encoding="utf-8") as f:
                            label = f.read().strip()
                    except Exception:
                        label = None
                    try:
                        with open(os.path.join(hw_path, fn), "r", encoding="utf-8") as f:
                            raw = f.read().strip()
                        if not raw:
                            continue
                        t = float(raw) / 1000.0
                    except Exception:
                        continue
                    key = f"{name}:{label or ('temp'+idx)}"[:18]
                    temps.setdefault(key, t)
        except Exception:
            pass

        return dict(sorted(temps.items(), key=lambda kv: kv[0].lower()))

    def pmic_rails(self) -> Tuple[Dict[str, float], Dict[str, float]]:
        raw = self.runner.vcgencmd("pmic_read_adc")
        volts: Dict[str, float] = {}
        amps: Dict[str, float] = {}
        if not raw:
            return volts, amps

        # Example lines vary; keep parsing tolerant.
        #   CORE_A current(0)=0.439
        #   CORE_V volt(0)=0.851
        pattern = re.compile(r"\s*([A-Z0-9_]+)_(A|V)\s+(?:current|volt)\(\d+\)=([\d\.]+)")
        for line in raw.splitlines():
            m = pattern.search(line)
            if not m:
                continue
            name, typ, val_s = m.groups()
            try:
                val = float(val_s)
            except Exception:
                continue
            if typ == "V":
                volts[name] = val
            else:
                amps[name] = val
        return volts, amps

    def power(self) -> Dict[str, object]:
        volts, amps = self.pmic_rails()
        input_v = float(volts.get("EXT5V", 0.0) or 0.0)
        monitored_w = 0.0
        rails: List[Dict[str, object]] = []

        for name in sorted(set(volts.keys()) | set(amps.keys())):
            if name in {"EXT5V", "BATT"}:
                continue
            v = float(volts.get(name, 0.0) or 0.0)
            a = float(amps.get(name, 0.0) or 0.0)
            w = v * a
            monitored_w += w
            category = "IO"
            if "CORE" in name:
                category = "CPU"
            elif "DDR" in name:
                category = "RAM"
            elif "HDMI" in name:
                category = "VID"
            rails.append({"cat": category, "name": name, "v": v, "a": a, "w": w})

        eff_drop = 0.02 if input_v and input_v < 4.9 else 0.0
        eff = _clamp(PMIC_EFFICIENCY_BASE - eff_drop, 0.75, 0.98)
        pmic_loss = monitored_w * (1.0 - eff)
        overhead = pmic_loss + UNMONITORED_OFFSET_W
        total_w = monitored_w + overhead
        total_a = (total_w / input_v) if input_v > 0 else 0.0

        rails.sort(key=lambda r: float(r["w"]), reverse=True)
        return {
            "input_v": input_v,
            "eff": eff,
            "monitored_w": monitored_w,
            "pmic_loss_w": pmic_loss,
            "overhead_w": overhead,
            "total_w": total_w,
            "total_a": total_a,
            "rails": rails,
            "raw_volts": volts,
            "raw_amps": amps,
        }

    def collect(self) -> Dict[str, object]:
        cpu = self.cpu_usage()
        cpu_avg = (sum(cpu.values()) / len(cpu)) if cpu else 0.0
        mem = self.mem()
        disks = self.disk_usage()
        temps = self.temps_c()
        freq = self.cpu_freq_mhz()
        thr = self.throttled_hex()
        load1, load5, load15 = self.load_avg()
        power = self.power()

        cpu_temp = float(temps.get("CPU", 0.0) or 0.0)
        self.cpu_avg_hist.append(cpu_avg)
        self.cpu0_temp_hist.append(cpu_temp)
        self.power_hist.append(float(power.get("total_w", 0.0) or 0.0))

        now = datetime.now(timezone.utc)
        return {
            "ts": now.isoformat(),
            "host": socket.gethostname(),
            "uptime_s": self.uptime_s(),
            "load": {"1": load1, "5": load5, "15": load15},
            "cpu": {
                "per_core": cpu,
                "avg": cpu_avg,
                "freq_mhz": freq,
            },
            "mem": mem,
            "disk": [
                {
                    "mount": d.mount,
                    "total_b": d.total_b,
                    "used_b": d.used_b,
                    "free_b": d.free_b,
                    "percent": d.percent,
                }
                for d in disks
            ],
            "temps_c": temps,
            "throttled_hex": thr,
            "power": power,
        }


class MetricsLogger:
    def __init__(self, path: str) -> None:
        self.path = os.path.expanduser(path)
        self.enabled = True
        self._fh: Optional[object] = None
        self._last_error: Optional[str] = None

    @property
    def last_error(self) -> Optional[str]:
        return self._last_error

    def _open_if_needed(self) -> None:
        if self._fh is not None:
            return
        parent = os.path.dirname(self.path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        self._fh = open(self.path, "a", encoding="utf-8")

    def write(self, obj: Dict[str, object]) -> None:
        if not self.enabled:
            return
        try:
            self._open_if_needed()
            assert self._fh is not None
            self._fh.write(json.dumps(obj, separators=(",", ":"), ensure_ascii=False) + "\n")
            self._fh.flush()
            self._last_error = None
        except Exception as e:
            self._last_error = str(e)

    def close(self) -> None:
        try:
            if self._fh is not None:
                self._fh.close()
        finally:
            self._fh = None


class LiveMonTui:
    def __init__(self, refresh_s: float, log_path: str, log_interval_s: float) -> None:
        self.refresh_s = max(0.2, float(refresh_s))
        self.log_interval_s = max(0.2, float(log_interval_s))
        self._history_len = int(round(HISTORY_SECONDS / self.refresh_s))
        self.collector = MetricsCollector(history_len=self._history_len)
        self.logger = MetricsLogger(log_path)
        self._last_log_t = 0.0
        self._paused = False
        self._show_help = False
        self._last_metrics: Optional[Dict[str, object]] = None

    def _throttle_messages(self, throttled_hex: int) -> Tuple[List[str], List[str]]:
        active: List[str] = []
        past: List[str] = []
        if throttled_hex:
            for bit, (msg, _sev) in THROTTLE_CODES.items():
                if (throttled_hex >> bit) & 1:
                    (active if bit < 16 else past).append(msg)
        return active, past

    def _draw_box(self, win: "curses.window", title: str, color: int = 0) -> None:
        try:
            win.box()
        except curses.error:
            return
        if title:
            _safe_addstr(win, 0, 2, f" {title} ", color | curses.A_BOLD)

    def _draw_header(self, win: "curses.window", m: Dict[str, object]) -> None:
        win.erase()
        h, w = win.getmaxyx()
        self._draw_box(win, "LiveMon", curses.color_pair(4))

        now_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        uptime = self.collector.uptime_str()
        load = m.get("load", {}) if isinstance(m.get("load"), dict) else {}
        load1 = float(load.get("1", 0.0) or 0.0)
        load5 = float(load.get("5", 0.0) or 0.0)
        load15 = float(load.get("15", 0.0) or 0.0)
        line1 = f" Host: {m.get('host','?')}   Up: {uptime}   Load: {load1:.2f} {load5:.2f} {load15:.2f}"
        line2 = f" Time: {now_local}   Refresh: {self.refresh_s:.1f}s   Logging: {'ON' if self.logger.enabled else 'OFF'}"
        if self.logger.enabled and self.logger.last_error:
            line2 = f" Time: {now_local}   Refresh: {self.refresh_s:.1f}s   Logging error: {self.logger.last_error[:40]}"

        _safe_addstr(win, 1, 2, line1[: max(0, w - 4)], curses.color_pair(6))
        _safe_addstr(win, 2, 2, line2[: max(0, w - 4)], curses.color_pair(6))

        win.noutrefresh()

    def _draw_cpu_mem_disk(self, win: "curses.window", m: Dict[str, object]) -> None:
        win.erase()
        h, w = win.getmaxyx()
        self._draw_box(win, "CPU / Memory / Storage", curses.color_pair(4))
        if h < 6 or w < 40:
            _safe_addstr(win, 1, 2, "Resize terminal", curses.color_pair(2))
            win.noutrefresh()
            return

        cpu = m.get("cpu", {}) if isinstance(m.get("cpu"), dict) else {}
        per_core = cpu.get("per_core", {}) if isinstance(cpu.get("per_core"), dict) else {}
        cpu_avg = float(cpu.get("avg", 0.0) or 0.0)
        freq = float(cpu.get("freq_mhz", 0.0) or 0.0)
        mem = m.get("mem", {}) if isinstance(m.get("mem"), dict) else {}
        disks = m.get("disk", []) if isinstance(m.get("disk"), list) else []

        y = 1
        bar_w = max(10, w - 26)
        _safe_addstr(win, y, 2, f"CPU Avg  {cpu_avg:5.1f}% ", curses.A_BOLD)
        _safe_addstr(win, y, 18, _render_bar(cpu_avg, bar_w), _color_by_percent(cpu_avg, CPU_WARN, 95.0))
        y += 1
        _safe_addstr(win, y, 2, f"Freq     {freq:6.0f} MHz", curses.color_pair(6))
        y += 1

        # Per-core list
        cores = sorted(per_core.keys(), key=lambda s: int(str(s).replace("cpu", ""))) if per_core else []
        max_core_lines = max(1, min(8, h - y - 8))
        for i, name in enumerate(cores[:max_core_lines]):
            v = float(per_core.get(name, 0.0) or 0.0)
            _safe_addstr(win, y, 2, f"{name.upper():>4} {v:5.1f}% ")
            _safe_addstr(win, y, 14, _render_bar(v, max(10, w - 18)), _color_by_percent(v, CPU_WARN, 95.0))
            y += 1

        y += 1
        # Memory
        ram_total = float(mem.get("ram_total_b", 0.0) or 0.0)
        ram_used = float(mem.get("ram_used_b", 0.0) or 0.0)
        ram_p = float(mem.get("ram_percent", 0.0) or 0.0)
        swap_total = float(mem.get("swap_total_b", 0.0) or 0.0)
        swap_used = float(mem.get("swap_used_b", 0.0) or 0.0)
        swap_p = float(mem.get("swap_percent", 0.0) or 0.0)

        _safe_addstr(win, y, 2, f"RAM  {_fmt_percent(ram_p)} {(_fmt_bytes(ram_used) + '/' + _fmt_bytes(ram_total)):<18}")
        _safe_addstr(win, y, 36, _render_bar(ram_p, max(10, w - 40)), _color_by_percent(ram_p, MEM_WARN, 97.0))
        y += 1
        _safe_addstr(win, y, 2, f"SWAP {_fmt_percent(swap_p)} {(_fmt_bytes(swap_used) + '/' + _fmt_bytes(swap_total)):<18}")
        _safe_addstr(win, y, 36, _render_bar(swap_p, max(10, w - 40)), _color_by_percent(swap_p, 50.0, 90.0))
        y += 2

        # Disk
        _safe_addstr(win, y, 2, "Storage", curses.A_BOLD)
        y += 1
        for d in disks[: max(1, h - y - 2)]:
            try:
                mount = str(d.get("mount", "?"))
                p = float(d.get("percent", 0.0) or 0.0)
                used = int(d.get("used_b", 0) or 0)
                total = int(d.get("total_b", 0) or 0)
            except Exception:
                continue
            _safe_addstr(win, y, 2, f"{mount:<14} {_fmt_percent(p)} {(_fmt_bytes(used)+'/'+_fmt_bytes(total)):<20}")
            _safe_addstr(win, y, 42, _render_bar(p, max(10, w - 46)), _color_by_percent(p, DISK_WARN, 97.0))
            y += 1

        win.noutrefresh()

    def _draw_temps_power(self, win: "curses.window", m: Dict[str, object]) -> None:
        win.erase()
        h, w = win.getmaxyx()
        self._draw_box(win, "Temperatures / Power", curses.color_pair(4))
        if h < 6 or w < 40:
            _safe_addstr(win, 1, 2, "Resize terminal", curses.color_pair(2))
            win.noutrefresh()
            return

        temps = m.get("temps_c", {}) if isinstance(m.get("temps_c"), dict) else {}
        thr = int(m.get("throttled_hex", 0) or 0)
        power = m.get("power", {}) if isinstance(m.get("power"), dict) else {}

        active, past = self._throttle_messages(thr)
        y = 1
        if active:
            _safe_addstr(win, y, 2, "ACTIVE: " + ", ".join(active)[: max(0, w - 10)], curses.color_pair(3) | curses.A_BOLD)
            y += 1
        elif past:
            _safe_addstr(win, y, 2, "PAST: " + ", ".join(past)[: max(0, w - 8)], curses.color_pair(2))
            y += 1
        else:
            _safe_addstr(win, y, 2, "STATUS: OK", curses.color_pair(1))
            y += 1

        input_v = float(power.get("input_v", 0.0) or 0.0)
        total_w = float(power.get("total_w", 0.0) or 0.0)
        total_a = float(power.get("total_a", 0.0) or 0.0)
        eff = float(power.get("eff", 0.0) or 0.0)

        _safe_addstr(win, y, 2, f"Input: {input_v:0.3f}V", _color_by_voltage(input_v) | curses.A_BOLD)
        _safe_addstr(win, y, 18, f"Total: {total_w:0.2f}W  ({total_a:0.3f}A)  Eff: {eff*100:0.1f}%", curses.color_pair(5) | curses.A_BOLD)
        y += 2

        # Temps list + sparkline for CPU
        cpu_t = float(temps.get("CPU", 0.0) or 0.0)
        spark_w = max(10, w - 28)
        _safe_addstr(win, y, 2, f"CPU: {cpu_t:5.1f}°C ", _color_by_temp(cpu_t) | curses.A_BOLD)
        _safe_addstr(win, y, 18, _sparkline(self.collector.cpu0_temp_hist, spark_w, max_val=max(85.0, cpu_t, 1.0)), curses.color_pair(6))
        y += 1

        # Additional temps
        other = [(k, float(v)) for k, v in temps.items() if k != "CPU"]
        max_lines = max(1, min(len(other), h - y - 9))
        for k, v in other[:max_lines]:
            _safe_addstr(win, y, 2, f"{k:<18} {v:5.1f}°C", _color_by_temp(v))
            y += 1

        y += 1
        _safe_addstr(win, y, 2, "Top Rails", curses.A_BOLD)
        y += 1
        rails = power.get("rails", []) if isinstance(power.get("rails"), list) else []
        for r in rails[: max(1, h - y - 2)]:
            try:
                cat = str(r.get("cat", ""))
                name = str(r.get("name", ""))
                v = float(r.get("v", 0.0) or 0.0)
                a = float(r.get("a", 0.0) or 0.0)
                wv = float(r.get("w", 0.0) or 0.0)
            except Exception:
                continue
            attr = curses.A_DIM
            if wv >= 2.0:
                attr = curses.A_BOLD
            elif wv >= 0.05:
                attr = curses.A_NORMAL
            _safe_addstr(win, y, 2, f"{cat:<3} {name:<12} {v:>6.3f}V {a:>6.3f}A {wv:>6.3f}W"[: max(0, w - 4)], attr)
            y += 1

        win.noutrefresh()

    def _draw_history(self, win: "curses.window") -> None:
        win.erase()
        h, w = win.getmaxyx()
        self._draw_box(win, "History", curses.color_pair(4))
        if h < 5 or w < 50:
            _safe_addstr(win, 1, 2, "Resize terminal", curses.color_pair(2))
            win.noutrefresh()
            return

        cpu_avg = self.collector.cpu_avg_hist
        temps = self.collector.cpu0_temp_hist
        power = self.collector.power_hist
        graph_w = max(10, w - 18)

        y = 1
        _safe_addstr(win, y, 2, "CPU% ", curses.A_BOLD)
        _safe_addstr(win, y, 8, _sparkline(cpu_avg, graph_w, 100.0), _color_by_percent((cpu_avg[-1] if cpu_avg else 0.0), CPU_WARN, 95.0))
        y += 1
        _safe_addstr(win, y, 2, "Temp ", curses.A_BOLD)
        _safe_addstr(win, y, 8, _sparkline(temps, graph_w, 85.0), _color_by_temp((temps[-1] if temps else 0.0)))
        y += 1
        _safe_addstr(win, y, 2, "Watt ", curses.A_BOLD)
        # autoscale power to keep sparkline informative
        max_p = max([float(x) for x in power], default=1.0)
        _safe_addstr(win, y, 8, _sparkline(power, graph_w, max(10.0, max_p)), curses.color_pair(5))
        y += 1

        if self._show_help:
            help_lines = [
                "Keys: q quit | p pause | l toggle logging | ? help | r reset history",
                "Notes: run without sudo using --no-sudo (power/throttle sensors may be missing).",
            ]
            for line in help_lines:
                if y >= h - 1:
                    break
                _safe_addstr(win, y, 2, line[: max(0, w - 4)], curses.A_DIM)
                y += 1

        win.noutrefresh()

    def _draw_footer(self, win: "curses.window") -> None:
        win.erase()
        h, w = win.getmaxyx()
        if h <= 0:
            return
        status = "q quit  p pause  l logging  ? help"
        if self._paused:
            status = "PAUSED - " + status
        _safe_addstr(win, 0, 2, status[: max(0, w - 4)], curses.A_DIM)
        win.noutrefresh()

    def run(self, stdscr: "curses.window") -> None:
        curses.curs_set(0)
        stdscr.nodelay(True)
        stdscr.keypad(True)
        _init_colors()

        next_tick = time.monotonic()
        while True:
            # input
            try:
                key = stdscr.getch()
            except Exception:
                key = -1
            if key in (ord("q"), ord("Q")):
                break
            if key in (ord("p"), ord("P")):
                self._paused = not self._paused
            if key in (ord("l"), ord("L")):
                self.logger.enabled = not self.logger.enabled
            if key in (ord("?"), ord("h"), ord("H")):
                self._show_help = not self._show_help
            if key in (ord("r"), ord("R")):
                self.collector.cpu_avg_hist.clear()
                self.collector.cpu0_temp_hist.clear()
                self.collector.power_hist.clear()

            now = time.monotonic()
            if now < next_tick:
                time.sleep(0.05)
                continue
            next_tick = now + self.refresh_s

            if not self._paused or self._last_metrics is None:
                metrics = self.collector.collect()
                self._last_metrics = metrics
            else:
                metrics = self._last_metrics

            # logging
            if self.logger.enabled and not self._paused:
                if (now - self._last_log_t) >= self.log_interval_s:
                    self.logger.write(metrics)
                    self._last_log_t = now

            # layout
            stdscr.erase()
            H, W = stdscr.getmaxyx()
            if H < 18 or W < 90:
                _safe_addstr(
                    stdscr,
                    0,
                    0,
                    "Terminal too small. Resize to at least 90x18.",
                    curses.color_pair(2) | curses.A_BOLD,
                )
                stdscr.noutrefresh()
                curses.doupdate()
                continue

            header_h = 4
            footer_h = 1
            main_h = H - header_h - footer_h
            left_w = W // 2
            right_w = W - left_w
            top_h = int(main_h * 0.65)
            bottom_h = main_h - top_h

            header = stdscr.derwin(header_h, W, 0, 0)
            left = stdscr.derwin(top_h, left_w, header_h, 0)
            right = stdscr.derwin(top_h, right_w, header_h, left_w)
            bottom = stdscr.derwin(bottom_h, W, header_h + top_h, 0)
            footer = stdscr.derwin(footer_h, W, H - 1, 0)

            self._draw_header(header, metrics)
            self._draw_cpu_mem_disk(left, metrics)
            self._draw_temps_power(right, metrics)
            self._draw_history(bottom)
            self._draw_footer(footer)

            curses.doupdate()


def _parse_args(argv: List[str]) -> Dict[str, object]:
    refresh = DEFAULT_REFRESH_S
    log_interval = 1.0
    log_path = ""
    no_sudo = False

    it = iter(argv[1:])
    for a in it:
        if a in ("--no-sudo",):
            no_sudo = True
        elif a in ("--refresh", "-r"):
            try:
                refresh = float(next(it))
            except Exception:
                pass
        elif a in ("--log",):
            try:
                log_path = str(next(it))
            except Exception:
                pass
        elif a in ("--log-interval",):
            try:
                log_interval = float(next(it))
            except Exception:
                pass

    if not log_path:
        if os.geteuid() == 0:
            log_path = "/var/log/livemon/metrics.jsonl"
        else:
            log_path = os.path.expanduser("~/.local/state/livemon/metrics.jsonl")

    return {
        "refresh": refresh,
        "log_path": log_path,
        "log_interval": log_interval,
        "no_sudo": no_sudo,
    }



if __name__ == "__main__":
    args = _parse_args(sys.argv)
    if not args.get("no_sudo"):
        ensure_root_or_reexec(sys.argv)
    try:
        tui = LiveMonTui(
            refresh_s=float(args["refresh"]),
            log_path=str(args["log_path"]),
            log_interval_s=float(args["log_interval"]),
        )
        curses.wrapper(tui.run)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            tui.logger.close()  # type: ignore[name-defined]
        except Exception:
            pass
        print("\nMonitor stopped.")
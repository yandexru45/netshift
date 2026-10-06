// The router's vital signs for the dashboard (netshift get_router_stats).

export interface RouterStats {
  uptime_seconds: number;
  load: [number, number, number];
  cpu_cores: number;
  ram_total_mb: number;
  ram_available_mb: number;
  flash_free_mb: number;
  tmp_free_mb: number;
  temperature_c: number | null;
}

const num = (value: unknown): number =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;

export function parseRouterStats(input: unknown): RouterStats | null {
  let data: unknown = input;

  if (typeof input === 'string') {
    try {
      data = JSON.parse(input);
    } catch {
      return null;
    }
  }

  if (!data || typeof data !== 'object') {
    return null;
  }

  const raw = data as Record<string, unknown>;

  if (typeof raw.uptime_seconds !== 'number') {
    return null;
  }

  const load = Array.isArray(raw.load) ? raw.load : [];

  return {
    uptime_seconds: num(raw.uptime_seconds),
    load: [num(load[0]), num(load[1]), num(load[2])],
    cpu_cores: Math.max(1, num(raw.cpu_cores)),
    ram_total_mb: num(raw.ram_total_mb),
    ram_available_mb: num(raw.ram_available_mb),
    flash_free_mb: num(raw.flash_free_mb),
    tmp_free_mb: num(raw.tmp_free_mb),
    temperature_c:
      typeof raw.temperature_c === 'number' ? raw.temperature_c : null,
  };
}

// "3 d 4 h", "4 h 5 min", "12 min", "40 s". The unit words are passed in so that
// they can be translated.
export function formatUptime(
  seconds: number,
  units: { d: string; h: string; min: string; s: string },
): string {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);

  if (days > 0) {
    return `${days} ${units.d} ${hours} ${units.h}`;
  }

  if (hours > 0) {
    return `${hours} ${units.h} ${minutes} ${units.min}`;
  }

  if (minutes > 0) {
    return `${minutes} ${units.min}`;
  }

  return `${seconds} ${units.s}`;
}

// Memory in use, in percent of the total (0 when the total is unknown).
export function ramUsedPercent(stats: RouterStats): number {
  if (stats.ram_total_mb <= 0) {
    return 0;
  }

  const used = stats.ram_total_mb - stats.ram_available_mb;

  return Math.min(
    100,
    Math.max(0, Math.round((used / stats.ram_total_mb) * 100)),
  );
}

// Load per core, as a share of one fully busy core: 100 = every core is busy.
export function loadPercent(stats: RouterStats): number {
  return Math.round((stats.load[0] / stats.cpu_cores) * 100);
}

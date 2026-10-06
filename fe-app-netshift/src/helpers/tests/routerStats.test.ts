import { describe, expect, it } from 'vitest';
import {
  formatUptime,
  loadPercent,
  parseRouterStats,
  ramUsedPercent,
} from '../routerStats';

const answer = {
  uptime_seconds: 270000,
  load: [0.52, 0.4, 0.31],
  cpu_cores: 2,
  ram_total_mb: 256,
  ram_available_mb: 64,
  flash_free_mb: 10,
  tmp_free_mb: 50,
  temperature_c: 61,
};

const units = { d: 'd', h: 'h', min: 'min', s: 's' };

describe('parseRouterStats', () => {
  it('reads the backend answer', () => {
    expect(parseRouterStats(JSON.stringify(answer))).toEqual(answer);
  });

  it('treats a missing temperature as unknown', () => {
    expect(
      parseRouterStats({ ...answer, temperature_c: null })?.temperature_c,
    ).toBeNull();
    expect(parseRouterStats({ uptime_seconds: 5 })?.temperature_c).toBeNull();
  });

  it('never reports a negative or non-number value', () => {
    const stats = parseRouterStats({
      ...answer,
      ram_total_mb: -1,
      load: ['x', null],
    });

    expect(stats?.ram_total_mb).toBe(0);
    expect(stats?.load).toEqual([0, 0, 0]);
  });

  it('refuses an answer that is not one', () => {
    expect(parseRouterStats('Usage: netshift')).toBeNull();
    expect(parseRouterStats(null)).toBeNull();
    expect(parseRouterStats({})).toBeNull();
  });
});

describe('formatUptime', () => {
  it.each([
    [270000, '3 d 3 h'],
    [14700, '4 h 5 min'],
    [720, '12 min'],
    [40, '40 s'],
    [0, '0 s'],
  ])('%i -> %s', (seconds, text) => {
    expect(formatUptime(seconds, units)).toBe(text);
  });
});

describe('ramUsedPercent and loadPercent', () => {
  it('counts the memory in use', () => {
    expect(ramUsedPercent(parseRouterStats(answer)!)).toBe(75);
  });

  it('does not divide by an unknown total', () => {
    expect(
      ramUsedPercent({ ...parseRouterStats(answer)!, ram_total_mb: 0 }),
    ).toBe(0);
  });

  it('keeps the memory share inside 0..100', () => {
    expect(
      ramUsedPercent({ ...parseRouterStats(answer)!, ram_available_mb: 9999 }),
    ).toBe(0);
  });

  it('shows the load as a share of the cores', () => {
    expect(loadPercent(parseRouterStats(answer)!)).toBe(26);
    expect(loadPercent({ ...parseRouterStats(answer)!, load: [4, 1, 1] })).toBe(
      200,
    );
  });
});

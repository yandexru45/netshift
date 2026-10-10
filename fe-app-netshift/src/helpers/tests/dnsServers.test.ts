import { describe, expect, it } from 'vitest';
import {
  dnsRoutesFromOptions,
  dnsRouteSection,
  dnsRouteVia,
  dnsRoutesToOptions,
  dnsServersFromOptions,
  dnsServersToOptions,
} from '../dnsServers';

describe('dnsServersFromOptions', () => {
  it('puts the main server first, then the pool', () => {
    expect(
      dnsServersFromOptions({
        dns_type: 'doh',
        dns_server: 'dns.google/dns-query',
        dns_pool_server: ['udp://1.1.1.1', 'dot://dns.quad9.net'],
      }),
    ).toEqual([
      'doh://dns.google/dns-query',
      'udp://1.1.1.1',
      'dot://dns.quad9.net',
    ]);
  });

  it('opens an old config that has no pool', () => {
    expect(
      dnsServersFromOptions({ dns_type: 'udp', dns_server: '8.8.8.8' }),
    ).toEqual(['udp://8.8.8.8']);
  });

  it('uses the backend defaults for options that are not set', () => {
    expect(dnsServersFromOptions({})).toEqual(['udp://8.8.8.8']);
  });

  it('drops empty pool entries', () => {
    expect(
      dnsServersFromOptions({
        dns_type: 'udp',
        dns_server: '1.1.1.1',
        dns_pool_server: ['', '  ', 'udp://9.9.9.9'],
      }),
    ).toEqual(['udp://1.1.1.1', 'udp://9.9.9.9']);
  });
});

describe('dnsServersToOptions', () => {
  it('splits the list into the stored options', () => {
    expect(
      dnsServersToOptions([
        'dot://dns.adguard-dns.com',
        'udp://1.1.1.1',
        'doq://dns.adguard-dns.com',
      ]),
    ).toEqual({
      dns_type: 'dot',
      dns_server: 'dns.adguard-dns.com',
      dns_pool_server: ['udp://1.1.1.1', 'doq://dns.adguard-dns.com'],
    });
  });

  it('keeps a port and a path of the main server', () => {
    expect(dnsServersToOptions(['doh://dns.nextdns.io/abc123'])).toEqual({
      dns_type: 'doh',
      dns_server: 'dns.nextdns.io/abc123',
      dns_pool_server: [],
    });
    expect(dnsServersToOptions(['udp://10.0.0.1:5353'])?.dns_server).toBe(
      '10.0.0.1:5353',
    );
  });

  it('round-trips a stored configuration', () => {
    const stored = {
      dns_type: 'doh',
      dns_server: 'dns.google/dns-query',
      dns_pool_server: ['udp://1.1.1.1'],
    };

    expect(dnsServersToOptions(dnsServersFromOptions(stored))).toEqual(stored);
  });

  it('refuses what cannot be stored', () => {
    expect(dnsServersToOptions([])).toBeNull();
    expect(dnsServersToOptions(['', ' '])).toBeNull();
    expect(dnsServersToOptions(['8.8.8.8'])).toBeNull();
    expect(dnsServersToOptions(['ftp://8.8.8.8'])).toBeNull();
    expect(dnsServersToOptions(['udp://'])).toBeNull();
  });
});

describe('dnsRoutesFromOptions / dnsRoutesToOptions', () => {
  it('reads the entries of dns_server_route', () => {
    expect(
      dnsRoutesFromOptions([
        'doh://dns.google/dns-query tunnel',
        'udp://1.1.1.1 direct',
        'dot://dns.quad9.net via:second',
      ]),
    ).toEqual({
      'doh://dns.google/dns-query': 'tunnel',
      'udp://1.1.1.1': 'direct',
      'dot://dns.quad9.net': 'via:second',
    });
  });

  it('skips entries that are not "<server> <route>"', () => {
    expect(
      dnsRoutesFromOptions([
        'udp://1.1.1.1',
        'udp://1.1.1.1 default',
        'udp://1.1.1.1 via:',
        ' tunnel',
        '',
      ]),
    ).toEqual({});
  });

  it('knows the section of a route', () => {
    expect(dnsRouteSection('via:second')).toBe('second');
    expect(dnsRouteSection('via:')).toBeNull();
    expect(dnsRouteSection('direct')).toBeNull();
    expect(dnsRouteVia('main')).toBe('via:main');
  });

  it('writes only what differs from the backend default, in list order', () => {
    expect(
      dnsRoutesToOptions(['udp://9.9.9.9', 'udp://1.1.1.1', 'dot://x'], {
        'udp://1.1.1.1': 'via:main',
        'udp://9.9.9.9': 'via:second',
        'dot://x': 'direct',
        'udp://gone': 'via:main',
      }),
    ).toEqual(['udp://9.9.9.9 via:second', 'udp://1.1.1.1 via:main']);
  });

  it('writes "direct" when the old global switch would send the server through the tunnel', () => {
    expect(
      dnsRoutesToOptions(
        ['udp://1.1.1.1', 'dot://x'],
        { 'udp://1.1.1.1': 'direct', 'dot://x': 'tunnel' },
        'tunnel',
      ),
    ).toEqual(['udp://1.1.1.1 direct']);
  });

  it('writes nothing when no server has its own route', () => {
    expect(dnsRoutesToOptions(['udp://1.1.1.1'], {})).toEqual([]);
  });

  it('ignores a route it does not know', () => {
    expect(
      dnsRoutesToOptions(['udp://1.1.1.1'], { 'udp://1.1.1.1': 'weird' }),
    ).toEqual([]);
  });

  it('round-trips', () => {
    const entries = ['udp://1.1.1.1 via:main', 'dot://dns.google via:second'];

    expect(
      dnsRoutesToOptions(
        ['udp://1.1.1.1', 'dot://dns.google'],
        dnsRoutesFromOptions(entries),
      ),
    ).toEqual(entries);
  });
});

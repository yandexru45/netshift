import { callBaseMethod } from './callBaseMethod';
import { ClashAPI, Padkap } from '../../types';

export const PadkapShellMethods = {
  checkDNSAvailable: async () =>
    callBaseMethod<Padkap.DnsCheckResult>(
      Padkap.AvailableMethods.CHECK_DNS_AVAILABLE,
    ),
  checkFakeIP: async () =>
    callBaseMethod<Padkap.FakeIPCheckResult>(
      Padkap.AvailableMethods.CHECK_FAKEIP,
    ),
  checkNftRules: async () =>
    callBaseMethod<Padkap.NftRulesCheckResult>(
      Padkap.AvailableMethods.CHECK_NFT_RULES,
    ),
  getStatus: async () =>
    callBaseMethod<Padkap.GetStatus>(Padkap.AvailableMethods.GET_STATUS),
  checkSingBox: async () =>
    callBaseMethod<Padkap.SingBoxCheckResult>(
      Padkap.AvailableMethods.CHECK_SING_BOX,
    ),
  getSingBoxStatus: async () =>
    callBaseMethod<Padkap.GetSingBoxStatus>(
      Padkap.AvailableMethods.GET_SING_BOX_STATUS,
    ),
  getClashApiProxies: async () =>
    callBaseMethod<ClashAPI.Proxies>(Padkap.AvailableMethods.CLASH_API, [
      Padkap.AvailableClashAPIMethods.GET_PROXIES,
    ]),
  getClashApiProxyLatency: async (tag: string) =>
    callBaseMethod<Padkap.GetClashApiProxyLatency>(
      Padkap.AvailableMethods.CLASH_API,
      [Padkap.AvailableClashAPIMethods.GET_PROXY_LATENCY, tag, '5000'],
    ),
  getClashApiGroupLatency: async (tag: string) =>
    callBaseMethod<Padkap.GetClashApiGroupLatency>(
      Padkap.AvailableMethods.CLASH_API,
      [Padkap.AvailableClashAPIMethods.GET_GROUP_LATENCY, tag, '10000'],
    ),
  setClashApiGroupProxy: async (group: string, proxy: string) =>
    callBaseMethod<unknown>(Padkap.AvailableMethods.CLASH_API, [
      Padkap.AvailableClashAPIMethods.SET_GROUP_PROXY,
      group,
      proxy,
    ]),
  restart: async () =>
    callBaseMethod<unknown>(
      Padkap.AvailableMethods.RESTART,
      [],
      '/etc/init.d/padkap',
    ),
  start: async () =>
    callBaseMethod<unknown>(
      Padkap.AvailableMethods.START,
      [],
      '/etc/init.d/padkap',
    ),
  stop: async () =>
    callBaseMethod<unknown>(
      Padkap.AvailableMethods.STOP,
      [],
      '/etc/init.d/padkap',
    ),
  enable: async () =>
    callBaseMethod<unknown>(
      Padkap.AvailableMethods.ENABLE,
      [],
      '/etc/init.d/padkap',
    ),
  disable: async () =>
    callBaseMethod<unknown>(
      Padkap.AvailableMethods.DISABLE,
      [],
      '/etc/init.d/padkap',
    ),
  globalCheck: async () =>
    callBaseMethod<unknown>(Padkap.AvailableMethods.GLOBAL_CHECK),
  showSingBoxConfig: async () =>
    callBaseMethod<unknown>(Padkap.AvailableMethods.SHOW_SING_BOX_CONFIG),
  checkLogs: async () =>
    callBaseMethod<unknown>(Padkap.AvailableMethods.CHECK_LOGS),
  getSystemInfo: async () =>
    callBaseMethod<Padkap.GetSystemInfo>(
      Padkap.AvailableMethods.GET_SYSTEM_INFO,
    ),
  subscriptionUpdate: async () =>
    callBaseMethod<unknown>(Padkap.AvailableMethods.SUBSCRIPTION_UPDATE),
};

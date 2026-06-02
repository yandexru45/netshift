import { callBaseMethod } from './callBaseMethod';
import { ClashAPI, NetShift } from '../../types';
import { executeShellCommand } from '../../../helpers';

interface SingBoxComponentActionResult {
  success: boolean;
  version?: string;
  message?: string;
}

export const NetShiftShellMethods = {
  checkDNSAvailable: async () =>
    callBaseMethod<NetShift.DnsCheckResult>(
      NetShift.AvailableMethods.CHECK_DNS_AVAILABLE,
    ),
  checkFakeIP: async () =>
    callBaseMethod<NetShift.FakeIPCheckResult>(
      NetShift.AvailableMethods.CHECK_FAKEIP,
    ),
  checkNftRules: async () =>
    callBaseMethod<NetShift.NftRulesCheckResult>(
      NetShift.AvailableMethods.CHECK_NFT_RULES,
    ),
  getStatus: async () =>
    callBaseMethod<NetShift.GetStatus>(NetShift.AvailableMethods.GET_STATUS),
  checkSingBox: async () =>
    callBaseMethod<NetShift.SingBoxCheckResult>(
      NetShift.AvailableMethods.CHECK_SING_BOX,
    ),
  getSingBoxStatus: async () =>
    callBaseMethod<NetShift.GetSingBoxStatus>(
      NetShift.AvailableMethods.GET_SING_BOX_STATUS,
    ),
  getClashApiProxies: async () =>
    callBaseMethod<ClashAPI.Proxies>(NetShift.AvailableMethods.CLASH_API, [
      NetShift.AvailableClashAPIMethods.GET_PROXIES,
    ]),
  getClashApiProxyLatency: async (tag: string) =>
    callBaseMethod<NetShift.GetClashApiProxyLatency>(
      NetShift.AvailableMethods.CLASH_API,
      [NetShift.AvailableClashAPIMethods.GET_PROXY_LATENCY, tag, '5000'],
    ),
  getClashApiGroupLatency: async (tag: string) =>
    callBaseMethod<NetShift.GetClashApiGroupLatency>(
      NetShift.AvailableMethods.CLASH_API,
      [NetShift.AvailableClashAPIMethods.GET_GROUP_LATENCY, tag, '10000'],
    ),
  setClashApiGroupProxy: async (group: string, proxy: string) =>
    callBaseMethod<unknown>(NetShift.AvailableMethods.CLASH_API, [
      NetShift.AvailableClashAPIMethods.SET_GROUP_PROXY,
      group,
      proxy,
    ]),
  restart: async () =>
    callBaseMethod<unknown>(
      NetShift.AvailableMethods.RESTART,
      [],
      '/etc/init.d/netshift',
    ),
  start: async () =>
    callBaseMethod<unknown>(
      NetShift.AvailableMethods.START,
      [],
      '/etc/init.d/netshift',
    ),
  stop: async () =>
    callBaseMethod<unknown>(
      NetShift.AvailableMethods.STOP,
      [],
      '/etc/init.d/netshift',
    ),
  enable: async () =>
    callBaseMethod<unknown>(
      NetShift.AvailableMethods.ENABLE,
      [],
      '/etc/init.d/netshift',
    ),
  disable: async () =>
    callBaseMethod<unknown>(
      NetShift.AvailableMethods.DISABLE,
      [],
      '/etc/init.d/netshift',
    ),
  globalCheck: async () =>
    callBaseMethod<unknown>(NetShift.AvailableMethods.GLOBAL_CHECK),
  showSingBoxConfig: async () =>
    callBaseMethod<unknown>(NetShift.AvailableMethods.SHOW_SING_BOX_CONFIG),
  checkLogs: async () =>
    callBaseMethod<unknown>(NetShift.AvailableMethods.CHECK_LOGS),
  getSystemInfo: async () =>
    callBaseMethod<NetShift.GetSystemInfo>(
      NetShift.AvailableMethods.GET_SYSTEM_INFO,
    ),
  subscriptionUpdate: async () =>
    callBaseMethod<unknown>(NetShift.AvailableMethods.SUBSCRIPTION_UPDATE),
  singBoxComponentAction: async (
    action: 'install_extended' | 'install_stable' | 'check_update',
  ): Promise<SingBoxComponentActionResult> => {
    const response = await executeShellCommand({
      command: '/usr/bin/netshift',
      args: ['component_action', 'sing_box', action],
      timeout: 600000,
    });

    if (response.stdout) {
      try {
        const parsed = JSON.parse(
          response.stdout,
        ) as SingBoxComponentActionResult;

        return {
          success: Boolean(parsed.success),
          version: parsed.version,
          message: parsed.message,
        };
      } catch (_e) {
        return {
          success: false,
          message: response.stdout,
        };
      }
    }

    return {
      success: false,
      message: response.stderr || '',
    };
  },
};

import { callBaseMethod } from './callBaseMethod';
import { ClashAPI, NetShift } from '../../types';
import { executeShellCommand } from '../../../helpers';
import {
  ComponentActionStartResponse,
  SingBoxComponentActionResult,
  parseComponentActionStatus,
  pollSingBoxComponentAction,
} from './pollSingBoxComponentAction';

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
    // `check_update` is a quick single call — not subject to the rpcd 30s wall —
    // so keep it on the SYNCHRONOUS `component_action` path (unchanged shape).
    if (action === 'check_update') {
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
    }

    // Install actions can take minutes — drive the async backend contract:
    // start the job, then poll `component_action_status` with short execs so
    // rpcd never kills a single long-running call.
    const startResponse = await executeShellCommand({
      command: '/usr/bin/netshift',
      args: ['component_action_async', 'sing_box', action],
    });

    let start: ComponentActionStartResponse | null = null;

    if (startResponse.stdout) {
      try {
        start = JSON.parse(
          startResponse.stdout,
        ) as ComponentActionStartResponse;
      } catch (_e) {
        start = null;
      }
    }

    if (!start || start.success !== true || !start.job_id) {
      return {
        success: false,
        message:
          start?.message || startResponse.stderr || _('Core switch failed'),
      };
    }

    const jobId = start.job_id;

    return pollSingBoxComponentAction(async () => {
      const statusResponse = await executeShellCommand({
        command: '/usr/bin/netshift',
        args: ['component_action_status', jobId],
      });

      if (!statusResponse.stdout) {
        return null;
      }

      return parseComponentActionStatus(statusResponse.stdout);
    });
  },
};

import { COMMAND_TIMEOUT } from '../constants';
import { withTimeout } from './withTimeout';
import { logger } from '../netshift';

interface ExecuteShellCommandParams {
  command: string;
  args: string[];
  timeout?: number;
  // Send the call as its own HTTP request. LuCI merges RPC calls made within
  // one animation frame into a single request that rpcd runs one call after
  // another, so batched commands never overlap and all answer at once.
  nobatch?: boolean;
}

interface ExecuteShellCommandResponse {
  stdout: string;
  stderr: string;
  code?: number;
}

let execNoBatch:
  | ((
      command: string,
      args: string[],
    ) => Promise<ExecuteShellCommandResponse | number>)
  | undefined;

// The read-only RPC entry point has its own backend allowlist. Select it for
// read methods so a read-only LuCI account can load status without granting
// access to the unrestricted NetShift command.
const READ_COMMANDS = new Set([
  'get_status',
  'get_sing_box_status',
  'get_core_capabilities',
  'get_lan_info',
  'get_geoip_flags',
  'get_update_notice',
  'get_system_info',
  'get_subscription_info',
  'get_pin_guard_events',
  'auto_update_status',
  'check_logs',
  'show_sing_box_config',
  'get_config_warnings',
]);
const READ_CLASH_COMMANDS = new Set([
  'get_proxies',
  'get_connections',
  'get_proxy_latency',
  'get_group_latency',
]);

function readOnlyCommand(command: string, args: string[]): string {
  if (command !== '/usr/bin/netshift') return command;
  if (
    READ_COMMANDS.has(args[0]) ||
    (args[0] === 'config_snapshot' && args[1] === 'list') ||
    (args[0] === 'clash_api' && READ_CLASH_COMMANDS.has(args[1]))
  ) {
    return '/usr/bin/netshift-read';
  }
  return command;
}

// Same ubus call as fs.exec, declared with nobatch. A non-object reply is the
// ubus status code of a failed call.
async function execWithoutBatching(
  command: string,
  args: string[],
): Promise<ExecuteShellCommandResponse> {
  execNoBatch ??= rpc.declare<ExecuteShellCommandResponse | number>({
    object: 'file',
    method: 'exec',
    params: ['command', 'params', 'env'],
    nobatch: true,
  });

  const reply = await execNoBatch(command, args);

  if (reply && typeof reply === 'object') {
    return reply;
  }

  return { stdout: '', stderr: `ubus status ${reply}`, code: Number(reply) };
}

export async function executeShellCommand({
  command,
  args,
  timeout = COMMAND_TIMEOUT,
  nobatch = false,
}: ExecuteShellCommandParams): Promise<ExecuteShellCommandResponse> {
  const executionCommand = readOnlyCommand(command, args);
  try {
    // Awaited so that a timeout or a failed call lands in the catch below
    // instead of rejecting the caller.
    return await withTimeout(
      nobatch
        ? execWithoutBatching(executionCommand, args)
        : fs.exec(executionCommand, args),
      timeout,
      [command, ...args].join(' '),
    );
  } catch (err) {
    const error = err as Error;

    // Callers only see an empty result, so keep the reason in the console.
    logger.warn('[SHELL]', `[${[command, ...args].join(' ')}]`, error?.message);

    return { stdout: '', stderr: error?.message, code: 0 };
  }
}

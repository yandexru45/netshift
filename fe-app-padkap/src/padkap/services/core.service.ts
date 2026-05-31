import { TabServiceInstance } from './tab.service';
import { store } from './store.service';
import { logger } from './logger.service';
import { PadkapLogWatcher } from './padkapLogWatcher.service';
import { PadkapShellMethods } from '../methods';

export function coreService() {
  TabServiceInstance.onChange((activeId, tabs) => {
    logger.info('[TAB]', activeId);
    store.set({
      tabService: {
        current: activeId || '',
        all: tabs.map((tab) => tab.id),
      },
    });
  });

  const watcher = PadkapLogWatcher.getInstance();

  watcher.init(
    async () => {
      const logs = await PadkapShellMethods.checkLogs();

      if (logs.success) {
        return logs.data as string;
      }

      return '';
    },
    {
      intervalMs: 3000,
      onNewLog: (line) => {
        if (
          line.toLowerCase().includes('[error]') ||
          line.toLowerCase().includes('[fatal]')
        ) {
          ui.addNotification('Padkap Error', E('div', {}, line), 'error');
        }
      },
    },
  );

  watcher.start();
}

import { PadkapShellMethods } from '../methods';
import { store } from '../services';

export async function fetchServicesInfo() {
  const [padkap, singbox] = await Promise.all([
    PadkapShellMethods.getStatus(),
    PadkapShellMethods.getSingBoxStatus(),
  ]);

  if (!padkap.success || !singbox.success) {
    store.set({
      servicesInfoWidget: {
        loading: false,
        failed: true,
        data: { singbox: 0, padkap: 0 },
      },
    });
  }

  if (padkap.success && singbox.success) {
    store.set({
      servicesInfoWidget: {
        loading: false,
        failed: false,
        data: { singbox: singbox.data.running, padkap: padkap.data.enabled },
      },
    });
  }
}

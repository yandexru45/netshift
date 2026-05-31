import { DIAGNOSTICS_CHECKS_MAP } from './contstants';
import { PadkapShellMethods } from '../../../methods';
import { updateCheckStore } from './updateCheckStore';
import { getMeta } from '../helpers/getMeta';

export async function runFakeIPCheck() {
  const { order, title, code } = DIAGNOSTICS_CHECKS_MAP.FAKEIP;

  updateCheckStore({
    order,
    code,
    title,
    description: _('Checking, please wait'),
    state: 'loading',
    items: [],
  });

  const routerFakeIPResponse = await PadkapShellMethods.checkFakeIP();

  const checks = {
    router: routerFakeIPResponse.success && routerFakeIPResponse.data.fakeip,
  };

  const allGood = checks.router;
  const atLeastOneGood = checks.router;

  const { state, description } = getMeta({ atLeastOneGood, allGood });

  updateCheckStore({
    order,
    code,
    title,
    description,
    state,
    items: [
      {
        state: checks.router ? 'success' : 'warning',
        key: checks.router
          ? _('Router DNS is routed through sing-box')
          : _('Router DNS is not routed through sing-box'),
        value: '',
      },
      {
        state: 'warning',
        key: _('Browser FakeIP check requires a public Padkap check endpoint'),
        value: '',
      },
    ],
  });
}

import { Padkap } from '../../types';

export async function getConfigSections(): Promise<Padkap.ConfigSection[]> {
  return uci.load('padkap').then(() => uci.sections('padkap'));
}

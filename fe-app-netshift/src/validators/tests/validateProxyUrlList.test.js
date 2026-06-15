import { describe, it, expect } from 'vitest';
import { validateProxyUrlList } from '../validateProxyUrlList';

// Synthetic placeholder links only — never real proxy/subscription data.
const VLESS =
  'vless://94792286-7bbe-4f33-8b36-18d1bbf70723@127.0.0.1:34520?type=tcp&encryption=none&security=none#node-a';
const SS =
  'ss://2022-blake3-aes-256-gcm:dmCly/Zh15Ww9+s+GFXiFTIkpw7c/qCISaBrai7WhhY=@127.0.0.1:27214?type=tcp#node-b';

const validBlobs = [
  ['single vless line', VLESS],
  ['single ss line', SS],
  ['two links', `${VLESS}\n${SS}`],
  ['blank lines ignored', `\n${VLESS}\n\n${SS}\n`],
  ['leading/trailing whitespace trimmed', `   ${VLESS}   \n\t${SS}\t`],
  ['CRLF tolerated', `${VLESS}\r\n${SS}\r`],
];

const invalidBlobs = [
  ['empty string', ''],
  ['whitespace/blank only', '   \n\t\n  '],
  ['unsupported scheme', 'tuic://127.0.0.1:443#node'],
  ['second line invalid', `${VLESS}\ntuic://127.0.0.1:443`],
  ['garbage line', 'not-a-link'],
];

describe('validateProxyUrlList', () => {
  describe.each(validBlobs)('Valid blob: %s', (_desc, blob) => {
    it('returns valid=true', () => {
      const res = validateProxyUrlList(blob);
      expect(res.valid).toBe(true);
    });
  });

  describe.each(invalidBlobs)('Invalid blob: %s', (_desc, blob) => {
    it('returns valid=false', () => {
      const res = validateProxyUrlList(blob);
      expect(res.valid).toBe(false);
      expect(typeof res.message).toBe('string');
      expect(res.message.length).toBeGreaterThan(0);
    });
  });

  it('reports the 1-based line number of the first failing line', () => {
    const res = validateProxyUrlList(`${VLESS}\n${SS}\ntuic://127.0.0.1:443`);
    expect(res.valid).toBe(false);
    expect(res.message).toContain('Line 3');
  });

  it('counts blank lines toward the reported line number', () => {
    const res = validateProxyUrlList(`${VLESS}\n\ntuic://127.0.0.1:443`);
    expect(res.valid).toBe(false);
    expect(res.message).toContain('Line 3');
  });
});

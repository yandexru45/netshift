import { ValidationResult } from './types';

export function validateIPV4(ip: string): ValidationResult {
  const ipRegex =
    /^(?:(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$/;

  if (ipRegex.test(ip)) {
    return { valid: true, message: _('Valid') };
  }

  return { valid: false, message: _('Invalid IP address') };
}

export function validateIPV6(ip: string): ValidationResult {
  const stripped = ip.replace(/^\[/, '').replace(/\]$/, '');
  const ipv6Regex = /^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$/;
  const ipv6CompressedRegex =
    /^([0-9a-fA-F]{0,4}:)*:([0-9a-fA-F]{0,4}:)*[0-9a-fA-F]{0,4}$/;

  if (ipv6Regex.test(stripped) || ipv6CompressedRegex.test(stripped)) {
    const colons = (stripped.match(/:/g) || []).length;

    if (colons >= 2 && colons <= 7) {
      return { valid: true, message: _('Valid') };
    }
  }

  return { valid: false, message: _('Invalid IPv6 address') };
}

export function validateIP(ip: string): ValidationResult {
  const ipv4 = validateIPV4(ip);

  if (ipv4.valid) {
    return ipv4;
  }

  return validateIPV6(ip);
}

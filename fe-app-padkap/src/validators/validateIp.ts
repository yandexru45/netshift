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
  // Strip brackets if present: [::1] -> ::1
  const stripped = ip.replace(/^\[/, '').replace(/\]$/, '');

  // Expanded-form regex: 2-7 groups of 0-4 hex digits separated by colons
  const ipv6Regex = /^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$/;

  // Compressed form: contains :: (at most one)
  const ipv6CompressedRegex = /^([0-9a-fA-F]{0,4}:)*:([0-9a-fA-F]{0,4}:)*[0-9a-fA-F]{0,4}$/;

  if (ipv6Regex.test(stripped) || ipv6CompressedRegex.test(stripped)) {
    // Additional sanity: colon count in compressed form
    const colons = (stripped.match(/:/g) || []).length;
    if (colons >= 2 && colons <= 7) {
      return { valid: true, message: _('Valid') };
    }
  }

  return { valid: false, message: _('Invalid IPv6 address') };
}

export function validateIP(ip: string): ValidationResult {
  const ipv4 = validateIPV4(ip);
  if (ipv4.valid) return ipv4;
  return validateIPV6(ip);
}

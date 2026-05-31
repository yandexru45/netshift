import { validateDomain } from './validateDomain';
import { validateIPV4, validateIPV6 } from './validateIp';
import { ValidationResult } from './types';

export function validateDNS(value: string): ValidationResult {
  if (!value) {
    return { valid: false, message: _('DNS server address cannot be empty') };
  }

  // Strip brackets from IPv6 addresses before validation
  const stripped = value.replace(/^\[/, '').replace(/\]$/, '');
  const cleanedValueWithoutPort = stripped.replace(/:(\d+)(?=\/|$)/, '');
  const cleanedIpWithoutPath = cleanedValueWithoutPort.split('/')[0];

  if (validateIPV4(cleanedIpWithoutPath).valid) {
    return { valid: true, message: _('Valid') };
  }

  if (validateIPV6(cleanedIpWithoutPath).valid) {
    return { valid: true, message: _('Valid') };
  }

  if (validateDomain(cleanedValueWithoutPort).valid) {
    return { valid: true, message: _('Valid') };
  }

  return {
    valid: false,
    message: _(
      'Invalid DNS server format. Examples: 8.8.8.8, [::1], or dns.example.com',
    ),
  };
}

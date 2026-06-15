import { ValidationResult } from './types';
import { validateProxyUrl } from './validateProxyUrl';

/**
 * Validate a textarea blob of proxy links (one per line).
 *
 * Splits on newlines, trims each line, ignores blank lines, then runs the
 * single-link `validateProxyUrl` on every remaining line. Returns the first
 * error encountered (annotated with the 1-based line number) or
 * `{ valid: true }` when every non-blank line is a valid proxy link.
 */
export function validateProxyUrlList(value: string): ValidationResult {
  const lines = value.split('\n');

  let hasLink = false;

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index].trim();

    if (line.length === 0) {
      continue;
    }

    hasLink = true;

    const validation = validateProxyUrl(line);

    if (!validation.valid) {
      return {
        valid: false,
        message: `${_('Line')} ${index + 1}: ${validation.message}`,
      };
    }
  }

  if (!hasLink) {
    return {
      valid: false,
      message: _('At least one proxy link must be specified.'),
    };
  }

  return { valid: true, message: '' };
}

// backend/src/utils/phone.js
// Minimal phone normalizer without external deps.
// NOTE: You can refine later with `libphonenumber-js` for stricter parsing.

const DEFAULT_CC = process.env.DEFAULT_COUNTRY_CODE || '+353'; // IE by default

function onlyDigits(s) {
  return (s || '').replace(/\D+/g, '');
}

/**
 * normalizePhone
 * @param {string} raw - user-provided phone number (e.g., "087 123 4567", "+353871234567", "0044 7700 900123")
 * @param {{ defaultCountryCode?: string }} [opts]
 * @returns {{ e164: string|null, reason?: string }}
 */
function normalizePhone(raw, opts = {}) {
  if (!raw || typeof raw !== 'string') {
    return { e164: null, reason: 'empty_or_invalid_input' };
  }

  const cc = opts.defaultCountryCode || DEFAULT_CC;
  let s = raw.trim();

  // Replace common visual separators
  s = s.replace(/[\s\-\(\)]/g, '');

  // 00 -> +
  if (s.startsWith('00')) {
    s = '+' + s.slice(2);
  }

  // If already starts with +, keep it; else apply country code
  if (s.startsWith('+')) {
    // keep
  } else {
    // If leading 0 and a country code is given, drop the leading zero before cc
    if (s.startsWith('0') && cc) {
      s = cc + s.slice(1);
    } else if (cc && !s.startsWith(cc.replace('+', ''))) {
      // Just prepend the country code if no plus present
      s = cc + s;
    }
  }

  // Now we expect + followed by digits
  if (!s.startsWith('+')) {
    s = '+' + s;
  }

  // Validate lengths (basic guard)
  const digits = onlyDigits(s);
  // E.164 max 15 digits (excluding '+'); lower bound ~8 for safety
  if (digits.length < 8 || digits.length > 15) {
    return { e164: null, reason: 'invalid_length' };
  }

  return { e164: '+' + digits };
}

/**
 * quickCheck: returns boolean feasibility (not strict validity)
 */
function isPossiblePhone(raw, opts) {
  const { e164 } = normalizePhone(raw, opts);
  return !!e164;
}

module.exports = {
  normalizePhone,
  isPossiblePhone,
};

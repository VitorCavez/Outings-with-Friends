function requireFields(fields, body) {
  const missing = fields.filter(field => !body[field]);
  if (missing.length > 0) {
    return `Missing required field(s): ${missing.join(', ')}`;
  }
  return null;
}

module.exports = { requireFields };

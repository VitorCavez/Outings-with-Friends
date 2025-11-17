const jwt = require('jsonwebtoken');

function optionalAuth(req, _res, next) {
  const h = req.headers?.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (token) {
    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET);
      req.user = { userId: payload.userId || payload.sub };
    } catch (_) {
      // invalid/expired -> treat as anonymous
    }
  }
  next();
}

module.exports = { optionalAuth };

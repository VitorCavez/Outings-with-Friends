// backend/src/routes/auth_middleware.js
const jwt = require('jsonwebtoken');

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];

  if (!authHeader) {
    console.log(
      '[auth] no Authorization header',
      req.method,
      req.originalUrl
    );
    return res
      .status(401)
      .json({ ok: false, error: 'TOKEN_MISSING' });
  }

  // Accept either "Bearer <token>" or just "<token>"
  const parts = authHeader.split(' ');
  const token =
    parts.length === 2 && /^bearer$/i.test(parts[0])
      ? parts[1]
      : authHeader;

  if (!token) {
    console.log(
      '[auth] empty token in header',
      req.method,
      req.originalUrl
    );
    return res
      .status(401)
      .json({ ok: false, error: 'TOKEN_MISSING' });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      console.log(
        '[auth] invalid token',
        req.method,
        req.originalUrl,
        '-', 
        err.message
      );
      return res
        .status(403)
        .json({ ok: false, error: 'INVALID_TOKEN' });
    }

    // Typical payload is { userId, email }
    req.user = user;
    console.log(
      '[auth] ok',
      req.method,
      req.originalUrl,
      'user=',
      JSON.stringify(user)
    );
    next();
  });
}

module.exports = { authenticateToken };

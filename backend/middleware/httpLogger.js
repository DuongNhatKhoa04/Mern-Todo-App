import logger from '../utils/logger.js';

// Express middleware: logs every HTTP request with method, URL, status, duration
const httpLogger = (req, res, next) => {
    const start = Date.now();

    res.on('finish', () => {
        const duration = Date.now() - start;

        // Escalate log level based on HTTP status code
        const level = res.statusCode >= 500 ? 'error'
            : res.statusCode >= 400 ? 'warn'
            : 'http';

        logger.log(level, `${req.method} ${req.originalUrl} ${res.statusCode}`, {
            method:      req.method,
            url:         req.originalUrl,
            statusCode:  res.statusCode,
            duration_ms: duration,
            ip:          req.ip,
            userAgent:   req.headers['user-agent'],
        });
    });

    next();
};

export default httpLogger;

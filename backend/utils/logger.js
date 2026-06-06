import winston from 'winston';
import { OpenTelemetryTransportV3 } from '@opentelemetry/winston-transport';
import { trace } from '@opentelemetry/api';

// Custom log levels: fatal > error > warn > info > http > debug
const LOG_LEVELS = {
    fatal: 0,
    error: 1,
    warn:  2,
    info:  3,
    http:  4,
    debug: 5,
};

const LOG_COLORS = {
    fatal: 'bold red',
    error: 'red',
    warn:  'yellow',
    info:  'green',
    http:  'magenta',
    debug: 'cyan',
};

winston.addColors(LOG_COLORS);

// Inject active OTel trace/span IDs into every log record
const injectTraceContext = winston.format((info) => {
    const activeSpan = trace.getActiveSpan();
    if (activeSpan) {
        const ctx = activeSpan.spanContext();
        info.traceId    = ctx.traceId;
        info.spanId     = ctx.spanId;
        info.traceFlags = ctx.traceFlags;
    }
    return info;
});

const logger = winston.createLogger({
    levels: LOG_LEVELS,
    level: process.env.LOG_LEVEL || 'info',

    // Structured JSON format (used by file + OTel transports)
    format: winston.format.combine(
        injectTraceContext(),
        winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
        winston.format.errors({ stack: true }),
        winston.format.json(),
    ),

    defaultMeta: { service: process.env.OTEL_SERVICE_NAME || 'mern-todo-backend' },

    transports: [
        // Human-readable coloured console output
        new winston.transports.Console({
            format: winston.format.combine(
                injectTraceContext(),
                winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
                winston.format.errors({ stack: true }),
                winston.format.colorize({ all: true }),
                winston.format.printf(({ timestamp, level, message, service, traceId, spanId, stack, ...meta }) => {
                    const traceInfo = traceId ? ` [trace=${traceId} span=${spanId}]` : '';
                    const metaStr   = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
                    const stackStr  = stack ? `\n${stack}` : '';
                    return `${timestamp} [${service}] ${level}: ${message}${traceInfo}${metaStr}${stackStr}`;
                }),
            ),
        }),

        // Bridge logs → OpenTelemetry Logs SDK → OTLP exporter
        new OpenTelemetryTransportV3(),
    ],
});

// File transports for production
if (process.env.NODE_ENV === 'production') {
    logger.add(new winston.transports.File({ filename: 'logs/error.log', level: 'error' }));
    logger.add(new winston.transports.File({ filename: 'logs/combined.log' }));
}

export default logger;

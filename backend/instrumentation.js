import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { BatchLogRecordProcessor } from '@opentelemetry/sdk-logs';
import { Resource } from '@opentelemetry/resources';

const otlpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318';

const sdk = new NodeSDK({
    resource: new Resource({
        'service.name': process.env.OTEL_SERVICE_NAME || 'mern-todo-backend',
        'service.version': process.env.npm_package_version || '1.0.0',
        'deployment.environment': process.env.NODE_ENV || 'development',
    }),

    // Traces — exported via OTLP HTTP
    traceExporter: new OTLPTraceExporter({
        url: `${otlpEndpoint}/v1/traces`,
    }),

    // Metrics — exported every 30s via OTLP HTTP
    metricReader: new PeriodicExportingMetricReader({
        exporter: new OTLPMetricExporter({
            url: `${otlpEndpoint}/v1/metrics`,
        }),
        exportIntervalMillis: parseInt(process.env.OTEL_METRIC_EXPORT_INTERVAL || '30000'),
    }),

    // Logs — exported via OTLP HTTP (bridged from Winston)
    logRecordProcessors: [
        new BatchLogRecordProcessor(
            new OTLPLogExporter({
                url: `${otlpEndpoint}/v1/logs`,
            })
        ),
    ],

    // Auto-instrumentation: HTTP, Express, Mongoose, DNS, Net...
    instrumentations: [
        getNodeAutoInstrumentations({
            // Disable fs instrumentation to reduce noise
            '@opentelemetry/instrumentation-fs': { enabled: false },
        }),
    ],
});

sdk.start();

process.on('SIGTERM', () => {
    sdk.shutdown()
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
});

process.on('SIGINT', () => {
    sdk.shutdown()
        .then(() => process.exit(0))
        .catch(() => process.exit(1));
});

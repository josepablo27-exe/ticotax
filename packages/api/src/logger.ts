// =============================================================================
// TicoTax SaaS — Logger (Pino)
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// [D] Plan Maestro PARTE 7: "Observabilidad | Pino + CloudWatch + Sentry"
// [D] PARTE 11: "Logs | stdout con JSON estructurado, sin archivos de log"
// =============================================================================

import pino from 'pino';

// Configuración de Pino según el entorno
const isProduction = process.env.NODE_ENV === 'production';

const pinoConfig: pino.LoggerOptions = {
  level: process.env.LOG_LEVEL || (isProduction ? 'info' : 'debug'),
  // [D] PARTE 11: Logs JSON estructurados
  transport: isProduction
    ? undefined // En prod, escribir JSON puro a stdout
    : {
        target: 'pino-pretty', // En dev, colorear para legibilidad
        options: {
          colorize: true,
          singleLine: false,
          translateTime: 'SYS:standard',
          ignore: 'pid,hostname',
        },
      },
  // [D] PARTE 11: Logs a stdout (Factor XI)
  // Los orquestadores (Docker, K8s) capturan stdout y lo envían a CloudWatch
};

export const logger = pino(pinoConfig);

// Child loggers para diferentes módulos
export const authLogger = logger.child({ module: 'auth' });
export const usuarioLogger = logger.child({ module: 'usuario' });
export const entidadLogger = logger.child({ module: 'entidad' });
export const facturaLogger = logger.child({ module: 'factura' });

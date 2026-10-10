// =============================================================================
// TicoTax SaaS — API Gateway (Fastify)
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// Base de la API: healthchecks, seguridad (Helmet, CORS, rate limit) y Swagger.
// Los plugins y controladores están separados en archivos dedicados.
//
// [D] Plan Maestro PARTE 2.1: "Node.js + TypeScript + Fastify | 24.x / 4.x"
// [D] PARTE 3.1: Endpoints con validación Zod
// [D] PARTE 4: OWASP Top 10 mitigations
// =============================================================================

import 'dotenv/config';
import Fastify, { FastifyInstance } from 'fastify';
import fastifyHelmet from '@fastify/helmet';
import fastifyRateLimit from '@fastify/rate-limit';
import fastifyCors from '@fastify/cors';
import fastifySwagger from '@fastify/swagger';
import fastifySwaggerUi from '@fastify/swagger-ui';
import { PrismaClient } from '@prisma/client';

import { logger } from './logger';

// =============================================================================
// ESTADO GLOBAL
// =============================================================================

const prisma = new PrismaClient();
let app: FastifyInstance | null = null;
let isShuttingDown = false;
let isReady = false;

// =============================================================================
// CREAR APLICACIÓN
// =============================================================================

async function createApp() {
  const instance = Fastify({
    logger: logger as any,
    requestIdLogLabel: 'reqId',
    disableRequestLogging: false,
    requestTimeout: 30000,
  });

  // ---------------------------------------------------------------------------
  // PLUGINS DE SEGURIDAD
  // ---------------------------------------------------------------------------

  // [D] PARTE 4 OWASP A05: Helmet para headers de seguridad
  await instance.register(fastifyHelmet, {
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
      },
    },
  });

  // OWASP A05: CORS restringido al origen del frontend (sin esto, cualquier
  // fetch directo del navegador hacia :3000 que no pase por el proxy de Vite
  // es bloqueado o, peor, quedaría abierto a "*" si se agregara sin allowlist).
  await instance.register(fastifyCors, {
    origin: (process.env.CORS_ALLOWED_ORIGINS || 'http://localhost:5173').split(','),
    credentials: true,
  });

  // [D] PARTE 4 OWASP A04: Rate limiting por IP
  await instance.register(fastifyRateLimit, {
    max: 100,
    timeWindow: '15 minutes',
  });

  // Swagger/OpenAPI — expone /docs (Fastify + JS/TS estricto no elimina la
  // necesidad de documentar el contrato HTTP para consumidores externos).
  await instance.register(fastifySwagger, {
    openapi: {
      info: {
        title: 'TicoTax API',
        description: 'API Gateway — Gestión de facturas electrónicas para Costa Rica',
        version: '0.1.0',
      },
    },
  });
  await instance.register(fastifySwaggerUi, {
    routePrefix: '/docs',
  });

  // ---------------------------------------------------------------------------
  // HEALTHCHECKS
  // ---------------------------------------------------------------------------

  instance.get('/health/live', async (request, reply) => {
    return reply.send({
      status: 'live',
      timestamp: new Date().toISOString(),
    });
  });

  instance.get('/health/ready', async (request, reply) => {
    if (!isReady) {
      return reply.status(503).send({
        status: 'not_ready',
        reason: 'Initializing',
        timestamp: new Date().toISOString(),
      });
    }

    if (isShuttingDown) {
      return reply.status(503).send({
        status: 'not_ready',
        reason: 'Shutting down',
        timestamp: new Date().toISOString(),
      });
    }

    return reply.send({
      status: 'ready',
      timestamp: new Date().toISOString(),
    });
  });

  // ---------------------------------------------------------------------------
  // RAÍZ
  // ---------------------------------------------------------------------------

  instance.get('/api/v1/', async (request, reply) => {
    return reply.send({
      service: 'ticotax-api',
      version: '0.1.0',
      status: 'operational',
      endpoints: {},
    });
  });

  // ---------------------------------------------------------------------------
  // HOOKS DEL CICLO DE VIDA
  // ---------------------------------------------------------------------------

  instance.addHook('onReady', async () => {
    const diagnostics = {
      postgresql: false,
      timestamp: new Date().toISOString(),
    };

    try {
      await prisma.$queryRaw`SELECT 1`;
      diagnostics.postgresql = true;
      logger.info('✓ PostgreSQL disponible');
    } catch (err) {
      logger.error({ err }, 'PostgreSQL no disponible');
      throw new Error(`Critical: PostgreSQL unavailable`);
    }

    isReady = true;
    logger.info(
      { diagnostics },
      '✓ API ready para recibir tráfico'
    );
  });

  instance.addHook('onClose', async () => {
    isShuttingDown = true;
    isReady = false;
    logger.info({ timestamp: new Date().toISOString() }, 'Recibido SIGTERM, drenando conexiones...');
    await prisma.$disconnect();
  });

  return instance;
}

// =============================================================================
// INICIAR SERVIDOR
// =============================================================================

async function start() {
  const HOST = process.env.API_HOST || '0.0.0.0';
  const PORT = parseInt(process.env.API_PORT || '3000', 10);

  try {
    app = await createApp();

    await app.listen({ host: HOST, port: PORT });

    logger.info(
      {
        service: 'ticotax-api',
        host: HOST,
        port: PORT,
        version: '0.1.0',
        endpoints: 0,
      },
      'TicoTax API iniciada y escuchando'
    );
  } catch (error) {
    console.error('ERROR DETALLADO:', error);
    logger.error({ error }, 'Error al iniciar API');
    process.exit(1);
  }
}

// =============================================================================
// GRACEFUL SHUTDOWN
// =============================================================================

process.on('SIGTERM', async () => {
  logger.info('SIGTERM recibido, iniciando graceful shutdown...');
  if (app) {
    await app.close();
  }
  process.exit(0);
});

// =============================================================================
// EJECUTAR SI ES EL ENTRY POINT
// =============================================================================

if (require.main === module) {
  start();
}

export default createApp;

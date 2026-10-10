// =============================================================================
// TicoTax SaaS — API Gateway (Fastify)
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// Autenticación + perfil del usuario (4 endpoints).
// Los plugins y controladores están separados en archivos dedicados.
//
// [D] Plan Maestro PARTE 2.1: "Node.js + TypeScript + Fastify | 24.x / 4.x"
// [D] PARTE 3.1: Endpoints con validación Zod
// [D] PARTE 4: OWASP Top 10 mitigations
// =============================================================================

import 'dotenv/config';
import Fastify, { FastifyInstance, FastifyRequest, FastifyReply, FastifyBaseLogger } from 'fastify';
import fastifyJwt from '@fastify/jwt';
import fastifyHelmet from '@fastify/helmet';
import fastifyRateLimit from '@fastify/rate-limit';
import fastifyCors from '@fastify/cors';
import fastifySwagger from '@fastify/swagger';
import fastifySwaggerUi from '@fastify/swagger-ui';
import { PrismaClient } from '@prisma/client';
import { ZodError } from 'zod';

import { logger } from './logger';
import { verifyJWT } from './verify-jwt.plugin';

// Controladores
import { AuthController } from './auth.controller';
import { UsuarioController } from './usuario.controller';

// =============================================================================
// EXTENSIÓN DE TIPOS PARA FASTIFY
// =============================================================================
declare module 'fastify' {
  interface FastifyInstance {
    verifyJWT: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

// Schemas
import {
  RegisterSchema,
  LoginSchema,
  RefreshSchema,
  RegisterInput,
  LoginInput,
  RefreshInput,
} from './schemas';

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
    logger: logger as unknown as FastifyBaseLogger,
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

  // [D] PARTE 3.1: JWT (Access Token 15min + Refresh Token 7 días)
  // OWASP A02: sin secreto no arrancamos — un fallback hardcodeado es un
  // secreto de facto que cualquiera puede leer en el código fuente.
  const jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret) {
    throw new Error('JWT_SECRET es obligatorio (ver .env.example). La API no puede arrancar sin él.');
  }

  await instance.register(fastifyJwt, {
    secret: jwtSecret,
    sign: {
      expiresIn: '15m',
    },
  });

  // Registrar el plugin verifyJWT de forma global
  instance.decorate('verifyJWT', verifyJWT);

  // ---------------------------------------------------------------------------
  // INSTANCIAR CONTROLADORES
  // ---------------------------------------------------------------------------

  const authController = new AuthController(prisma);
  const usuarioController = new UsuarioController(prisma);

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
      endpoints: {
        auth: {
          register: 'POST /auth/register',
          login: 'POST /auth/login',
          refresh: 'POST /auth/refresh',
        },
        usuarios: {
          me: 'GET /usuarios/me',
        },
      },
    });
  });

  // ---------------------------------------------------------------------------
  // RUTAS — AUTH (Públicas)
  // ==========================================================================

  instance.post<{ Body: RegisterInput }>('/auth/register', async (request, reply) => {
    try {
      request.body = RegisterSchema.parse(request.body);
      return await authController.register(request, reply);
    } catch (error) {
      if (error instanceof ZodError) {
        return reply.status(400).send({
          statusCode: 400,
          message: 'Validación fallida',
          errors: error.errors,
          timestamp: new Date().toISOString(),
        });
      }
      throw error;
    }
  });

  instance.post<{ Body: LoginInput }>(
    '/auth/login',
    // OWASP A07: límite estricto por IP en login para frenar fuerza bruta,
    // más agresivo que el límite global de la API.
    { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } },
    async (request, reply) => {
      try {
        request.body = LoginSchema.parse(request.body);
        return await authController.login(request, reply);
      } catch (error) {
        if (error instanceof ZodError) {
          return reply.status(400).send({
            statusCode: 400,
            message: 'Validación fallida',
            errors: error.errors,
            timestamp: new Date().toISOString(),
          });
        }
        throw error;
      }
    }
  );

  instance.post<{ Body: RefreshInput }>('/auth/refresh', async (request, reply) => {
    try {
      request.body = RefreshSchema.parse(request.body);
      return await authController.refresh(request, reply);
    } catch (error) {
      if (error instanceof ZodError) {
        return reply.status(400).send({
          statusCode: 400,
          message: 'Validación fallida',
          errors: error.errors,
          timestamp: new Date().toISOString(),
        });
      }
      throw error;
    }
  });

  // ---------------------------------------------------------------------------
  // RUTAS — USUARIOS (Protegidas)
  // ==========================================================================

  instance.get<{ Params: {} }>('/usuarios/me', { onRequest: [instance.verifyJWT] }, (request, reply) =>
    usuarioController.getMe(request, reply)
  );

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
        endpoints: 4,
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

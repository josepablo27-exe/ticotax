// =============================================================================
// TicoTax SaaS — Verify JWT Plugin
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// [D] Plan Maestro PARTE 3.1: "Middleware verifyJWT para RBAC"
// [D] PARTE 4: OWASP A07 — Identificación y autenticación
//
// Este plugin se registra en Fastify y protege las rutas que lo requieran.
// El decorator @fastify/jwt maneja la firma/verificación de tokens.
// =============================================================================

import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import '@fastify/jwt';
import { logger } from './logger';
import { JwtPayload } from './schemas';

// Tipa `request.user` (inyectado por @fastify/jwt tras jwtVerify()) con el
// shape real del payload de acceso, en vez de leerlo con `as any` en cada
// controlador.
declare module '@fastify/jwt' {
  interface FastifyJWT {
    user: JwtPayload;
  }
}

/**
 * Hook onRequest que verifica el JWT si la ruta lo requiere.
 *
 * Uso:
 *   app.get('/ruta-protegida', { onRequest: [app.verifyJWT] }, (req, reply) => {
 *     const usuarioId = (req as any).user.sub;
 *   })
 */
export async function verifyJWT(
  request: FastifyRequest,
  reply: FastifyReply
) {
  try {
    // @fastify/jwt inyecta el método authenticate() en request
    await request.jwtVerify();

    // Si llegamos aquí, el JWT es válido
    // El payload del JWT está disponible en request.user (inyectado por fastify-jwt)
    const user = request.user;

    logger.debug(
      { usuarioId: user.sub, email: user.email },
      'JWT verificado exitosamente'
    );
  } catch (error) {
    // Token inválido, expirado o no presente
    logger.warn(
      { error: (error as any).message },
      'Error al verificar JWT'
    );

    return reply.status(401).send({
      statusCode: 401,
      message: 'No autorizado. Token inválido o expirado.',
      timestamp: new Date().toISOString(),
    });
  }
}

/**
 * Decorador para proteger una ruta con JWT verification.
 * Usa el hook verifyJWT.
 */
export async function jwtProtectedRoute(
  app: FastifyInstance
) {
  // Este plugin se registra en el servidor principal (server.ts)
  // Las rutas que lo necesitan usan: { onRequest: [app.verifyJWT] }
  app.decorate('verifyJWT', verifyJWT);
}

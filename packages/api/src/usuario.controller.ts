// =============================================================================
// TicoTax SaaS — Usuario Controller
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
// =============================================================================

import { FastifyRequest, FastifyReply } from 'fastify';
import { PrismaClient } from '@prisma/client';
import { JwtPayload } from './schemas';
import { logger } from './logger';

export class UsuarioController {
  constructor(private prisma: PrismaClient) {}

  // ---------------------------------------------------------------------------
  // ME — Obtener datos del usuario autenticado
  // GET /usuarios/me
  // Protegido: requiere JWT válido
  // ---------------------------------------------------------------------------
  async getMe(
    request: FastifyRequest<{ Params: {} }>,
    reply: FastifyReply
  ) {
    try {
      // El JWT payload está disponible en request.user (inyectado por verifyJWT plugin)
      const usuarioId = request.user?.sub;

      if (!usuarioId) {
        return reply.status(401).send({
          statusCode: 401,
          message: 'No autenticado',
          timestamp: new Date().toISOString(),
        });
      }

      const usuario = await this.prisma.usuario.findUnique({
        where: { id: usuarioId },
        select: {
          id: true,
          email: true,
          nombre: true,
          rol: true,
          cedula: true,
          activo: true,
          emailVerificado: true,
          createdAt: true,
        },
      });

      if (!usuario) {
        return reply.status(404).send({
          statusCode: 404,
          message: 'Usuario no encontrado',
          timestamp: new Date().toISOString(),
        });
      }

      return reply.send(usuario);
    } catch (error) {
      logger.error({ error }, 'Error al obtener usuario actual');
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }
}

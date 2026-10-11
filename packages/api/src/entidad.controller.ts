// =============================================================================
// TicoTax SaaS — Entidad Controller
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// [D] Plan Maestro PARTE 5.1: tabla entidades con owner_id y vinculos_contables
// =============================================================================

import { FastifyRequest, FastifyReply } from 'fastify';
import { PrismaClient } from '@prisma/client';
import { EntidadCreateInput } from './schemas';
import { logger } from './logger';

export class EntidadController {
  constructor(private prisma: PrismaClient) {}

  // ---------------------------------------------------------------------------
  // GET /entidades — Listar entidades del usuario autenticado (paginado)
  // Protegido: requiere JWT válido
  // ---------------------------------------------------------------------------
  async list(
    request: FastifyRequest<{ Querystring: { page?: string; limit?: string } }>,
    reply: FastifyReply
  ) {
    try {
      const usuarioId = request.user?.sub;
      const page = Math.max(1, parseInt(request.query.page || '1', 10));
      const limit = Math.min(100, parseInt(request.query.limit || '10', 10));
      const skip = (page - 1) * limit;

      const [entidades, total] = await Promise.all([
        this.prisma.entidad.findMany({
          where: { ownerId: usuarioId },
          skip,
          take: limit,
          select: {
            id: true,
            nombre: true,
            cedulaJuridica: true,
            activo: true,
            createdAt: true,
          },
          orderBy: { createdAt: 'desc' },
        }),
        this.prisma.entidad.count({
          where: { ownerId: usuarioId },
        }),
      ]);

      return reply.send({
        data: entidades,
        total,
        page,
        pageSize: limit,
      });
    } catch (error: any) {
      logger.error(
        {
          errMessage: error?.message,
          errStack: error?.stack,
        },
        'Error al listar entidades'
      );
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }

  // ---------------------------------------------------------------------------
  // POST /entidades — Crear nueva entidad
  // Protegido: requiere JWT válido
  // ---------------------------------------------------------------------------
  async create(
    request: FastifyRequest<{ Body: EntidadCreateInput }>,
    reply: FastifyReply
  ) {
    try {
      const usuarioId = request.user?.sub;
      const { nombre, cedulaJuridica, tipoCedula, email } = request.body;

      if (!nombre || nombre.trim().length === 0) {
        return reply.status(400).send({
          statusCode: 400,
          message: 'El nombre de la entidad es requerido',
          timestamp: new Date().toISOString(),
        });
      }

      const entidad = await this.prisma.entidad.create({
        data: {
          ownerId: usuarioId,
          nombre,
          cedulaJuridica,
          tipoCedula,
          email,
          activo: true,
        },
        select: {
          id: true,
          nombre: true,
          cedulaJuridica: true,
          tipoCedula: true,
          email: true,
          activo: true,
          createdAt: true,
        },
      });

      logger.info(
        { entidadId: entidad.id, usuarioId },
        'Entidad creada exitosamente'
      );

      return reply.status(201).send(entidad);
    } catch (error: any) {
      if (error?.code === 'P2002') {
        return reply.status(409).send({
          statusCode: 409,
          message: 'La cédula jurídica ya está registrada',
          timestamp: new Date().toISOString(),
        });
      }

      logger.error(
        {
          errMessage: error?.message,
          errStack: error?.stack,
        },
        'Error al crear entidad'
      );
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }
}

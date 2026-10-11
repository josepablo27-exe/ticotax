// =============================================================================
// TicoTax SaaS — Factura Controller
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// [D] Plan Maestro PARTE 5.1: tabla facturas con índices estratégicos
// [D] PARTE 8.3: Procesamiento asincrónico via SQS (TICOTAX-202)
// =============================================================================

import { FastifyRequest, FastifyReply } from 'fastify';
import { PrismaClient } from '@prisma/client';
import { FacturaCreateInput } from './schemas';
import { logger } from './logger';

export class FacturaController {
  constructor(private prisma: PrismaClient) {}

  // ---------------------------------------------------------------------------
  // GET /facturas — Listar facturas de una entidad (paginado)
  // Protegido: requiere JWT válido
  // ---------------------------------------------------------------------------
  async list(
    request: FastifyRequest<{
      Querystring: { entidadId?: string; page?: string; limit?: string };
    }>,
    reply: FastifyReply
  ) {
    try {
      const usuarioId = request.user?.sub;
      const { entidadId, page: pageStr = '1', limit: limitStr = '10' } = request.query;

      if (!entidadId) {
        return reply.status(400).send({
          statusCode: 400,
          message: 'Se requiere el parámetro entidadId',
          timestamp: new Date().toISOString(),
        });
      }

      const entidad = await this.prisma.entidad.findUnique({
        where: { id: entidadId },
      });

      if (!entidad || entidad.ownerId !== usuarioId) {
        return reply.status(403).send({
          statusCode: 403,
          message: 'No tienes permiso para acceder a esta entidad',
          timestamp: new Date().toISOString(),
        });
      }

      const page = Math.max(1, parseInt(pageStr, 10));
      const limit = Math.min(100, parseInt(limitStr, 10));
      const skip = (page - 1) * limit;

      const [facturas, total] = await Promise.all([
        this.prisma.factura.findMany({
          where: { entidadId },
          skip,
          take: limit,
          orderBy: { createdAt: 'desc' },
        }),
        this.prisma.factura.count({
          where: { entidadId },
        }),
      ]);

      return reply.send({
        data: facturas,
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
        'Error al listar facturas'
      );
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }

  // ---------------------------------------------------------------------------
  // POST /facturas — Crear/ingestar nueva factura
  // Protegido: requiere JWT válido
  // ---------------------------------------------------------------------------
  async create(
    request: FastifyRequest<{ Body: FacturaCreateInput }>,
    reply: FastifyReply
  ) {
    try {
      const usuarioId = request.user?.sub;
      const { entidadId, moneda, descripcion } = request.body;

      // El schema ya normaliza monto/montoTotal a un número (schemas.ts);
      // se usa tal cual, sin volver a adivinar el nombre del campo.
      const monto = request.body.monto ?? 0;

      // Verificar que el usuario es propietario de la entidad
      const entidad = await this.prisma.entidad.findUnique({
        where: { id: entidadId },
      });

      if (!entidad || entidad.ownerId !== usuarioId) {
        return reply.status(403).send({
          statusCode: 403,
          message: 'No tienes permiso para crear facturas en esta entidad',
          timestamp: new Date().toISOString(),
        });
      }

      // Crear factura con valores inspeccionados
      const factura = await this.prisma.factura.create({
        data: {
          entidadId,
          monto,
          moneda,
          descripcion,
          estado: 'PENDIENTE',
        },
      });

      logger.info(
        { facturaId: factura.id, entidadId, monto },
        'Factura registrada exitosamente'
      );

      return reply.status(201).send(factura);
    } catch (error: any) {
      if (error?.code === 'P2002') {
        return reply.status(409).send({
          statusCode: 409,
          message: 'La factura o clave ya se encuentra registrada',
          timestamp: new Date().toISOString(),
        });
      }

      logger.error(
        {
          errMessage: error?.message,
          errStack: error?.stack,
        },
        'Error al crear factura'
      );
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }


  // ---------------------------------------------------------------------------
  // GET /facturas/:id — Obtener una factura específica
  // Protegido: requiere JWT válido
  // ---------------------------------------------------------------------------
  async getById(
    request: FastifyRequest<{ Params: { id: string } }>,
    reply: FastifyReply
  ) {
    try {
      const usuarioId = request.user?.sub;
      const { id } = request.params;

      const factura = await this.prisma.factura.findUnique({
        where: { id },
        include: { entidad: true },
      });

      if (!factura) {
        return reply.status(404).send({
          statusCode: 404,
          message: 'Factura no encontrada',
          timestamp: new Date().toISOString(),
        });
      }

      if (factura.entidad?.ownerId !== usuarioId) {
        return reply.status(403).send({
          statusCode: 403,
          message: 'No tienes permiso para acceder a esta factura',
          timestamp: new Date().toISOString(),
        });
      }

      return reply.send(factura);
    } catch (error: any) {
      logger.error(
        {
          errMessage: error?.message,
          errStack: error?.stack,
        },
        'Error al obtener factura'
      );
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }
}

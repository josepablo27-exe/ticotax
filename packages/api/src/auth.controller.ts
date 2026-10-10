// =============================================================================
// TicoTax SaaS — Auth Controller
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// [D] Plan Maestro PARTE 3.1: Login/Register/Refresh con JWT y RTR
// [D] PARTE 4: bcrypt BCRYPT_ROUNDS=12 (hasheado de contraseñas)
// =============================================================================

import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcrypt';
import { RegisterInput, LoginInput, RefreshInput } from './schemas';
import { logger } from './logger';

// [D] PARTE 8.2: valores del ConfigMap ticotax-config — Factor III (Config),
// se leen de env con el mismo default que documenta .env.example.
// JWT_EXPIRY / REFRESH_TOKEN_EXPIRY están en segundos (ver .env.example);
// @fastify/jwt, si `expiresIn` es un number, lo interpreta como segundos y
// lo convierte a ms internamente (jwt.js:convertToMs) — no hay que
// multiplicar acá, o el token expira 1000x más tarde de lo esperado.
const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS || '12', 10);
const ACCESS_TOKEN_EXPIRY_SECONDS = parseInt(process.env.JWT_EXPIRY || '900', 10);
const REFRESH_TOKEN_EXPIRY_SECONDS = parseInt(process.env.REFRESH_TOKEN_EXPIRY || '604800', 10);

export class AuthController {
  constructor(private prisma: PrismaClient) {}

  // @fastify/jwt decora `fastify.jwt` (no `request.jwt`) con sign/verify/decode.
  private getJwtSigner(request: FastifyRequest): FastifyInstance['jwt'] {
    const jwtSigner = request.server?.jwt;
    if (!jwtSigner) {
      throw new Error('El plugin @fastify/jwt no se encuentra disponible en la petición.');
    }
    return jwtSigner;
  }

  // ---------------------------------------------------------------------------
  // REGISTER — Crear nuevo usuario
  // POST /auth/register
  // ---------------------------------------------------------------------------
  async register(
    request: FastifyRequest<{ Body: RegisterInput }>,
    reply: FastifyReply
  ) {
    const { email, nombre, password, cedula, rol } = request.body;

    try {
      // Verificar que el email no existe ya
      const existingUser = await this.prisma.usuario.findUnique({
        where: { email },
      });

      if (existingUser) {
        return reply.status(409).send({
          statusCode: 409,
          message: 'El email ya está registrado',
          timestamp: new Date().toISOString(),
        });
      }

      // Hashear contraseña con bcrypt
      // [D] PARTE 4: bcrypt BCRYPT_ROUNDS=12
      const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

      // Crear usuario en BD
      const usuario = await this.prisma.usuario.create({
        data: {
          email,
          nombre,
          passwordHash,
          cedula,
          rol,
          activo: true,
          emailVerificado: false,
        },
      });

      // Obtener firmador JWT
      const jwtSigner = this.getJwtSigner(request);

      // Generar JWT tokens
      // [D] PARTE 3.1: "JWT (Access Token = 15min, Refresh Token = 7 días)"
      const accessToken = jwtSigner.sign(
        {
          sub: usuario.id,
          email: usuario.email,
          rol: usuario.rol,
        },
        { expiresIn: ACCESS_TOKEN_EXPIRY_SECONDS }
      );

      const refreshToken = jwtSigner.sign(
        {
          sub: usuario.id,
          email: usuario.email,
          type: 'refresh',
        },
        { expiresIn: REFRESH_TOKEN_EXPIRY_SECONDS }
      );

      logger.info(
        { usuarioId: usuario.id, email: usuario.email },
        'Usuario registrado exitosamente'
      );

      return reply.status(201).send({
        accessToken,
        refreshToken,
        usuario: {
          id: usuario.id,
          email: usuario.email,
          nombre: usuario.nombre,
          rol: usuario.rol,
        },
      });
    } catch (error: any) {
      logger.error(
        {
          errMessage: error?.message,
          errStack: error?.stack,
          errName: error?.name,
        },
        'Error al registrar usuario'
      );
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }

  // ---------------------------------------------------------------------------
  // LOGIN — Autenticarse con email y contraseña
  // POST /auth/login
  // ---------------------------------------------------------------------------
  async login(
    request: FastifyRequest<{ Body: LoginInput }>,
    reply: FastifyReply
  ) {
    const { email, password } = request.body;

    try {
      // Buscar usuario
      const usuario = await this.prisma.usuario.findUnique({
        where: { email },
      });

      if (!usuario) {
        return reply.status(401).send({
          statusCode: 401,
          message: 'Email o contraseña inválidos',
          timestamp: new Date().toISOString(),
        });
      }

      // Verificar contraseña
      const isPasswordValid = await bcrypt.compare(password, usuario.passwordHash);

      if (!isPasswordValid) {
        return reply.status(401).send({
          statusCode: 401,
          message: 'Email o contraseña inválidos',
          timestamp: new Date().toISOString(),
        });
      }

      // Verificar que el usuario esté activo
      if (!usuario.activo) {
        return reply.status(403).send({
          statusCode: 403,
          message: 'Usuario desactivado',
          timestamp: new Date().toISOString(),
        });
      }

      // Obtener firmador JWT
      const jwtSigner = this.getJwtSigner(request);

      // Generar tokens
      const accessToken = jwtSigner.sign(
        {
          sub: usuario.id,
          email: usuario.email,
          rol: usuario.rol,
        },
        { expiresIn: ACCESS_TOKEN_EXPIRY_SECONDS }
      );

      const refreshToken = jwtSigner.sign(
        {
          sub: usuario.id,
          email: usuario.email,
          type: 'refresh',
        },
        { expiresIn: REFRESH_TOKEN_EXPIRY_SECONDS }
      );

      // Actualizar último acceso
      await this.prisma.usuario.update({
        where: { id: usuario.id },
        data: { ultimoAcceso: new Date() },
      });

      logger.info(
        { usuarioId: usuario.id, email: usuario.email },
        'Usuario autenticado exitosamente'
      );

      return reply.send({
        accessToken,
        refreshToken,
        usuario: {
          id: usuario.id,
          email: usuario.email,
          nombre: usuario.nombre,
          rol: usuario.rol,
        },
      });
    } catch (error: any) {
      logger.error(
        {
          errMessage: error?.message,
          errStack: error?.stack,
          errName: error?.name,
        },
        'Error al hacer login'
      );
      return reply.status(500).send({
        statusCode: 500,
        message: 'Error interno del servidor',
        timestamp: new Date().toISOString(),
      });
    }
  }

  // ---------------------------------------------------------------------------
  // REFRESH — Obtener nuevo access token usando refresh token
  // POST /auth/refresh
  // [D] PARTE 3.1: "Refresh Token Rotation (RTR)"
  // ---------------------------------------------------------------------------
  async refresh(
    request: FastifyRequest<{ Body: RefreshInput }>,
    reply: FastifyReply
  ) {
    const { refreshToken } = request.body;

    try {
      const jwtSigner = this.getJwtSigner(request);

      // Verificar el refresh token
      const payload = jwtSigner.verify(refreshToken) as any;

      // Verificar que sea un refresh token (no un access token)
      if (payload.type !== 'refresh') {
        return reply.status(401).send({
          statusCode: 401,
          message: 'Token inválido',
          timestamp: new Date().toISOString(),
        });
      }

      // Obtener usuario
      const usuario = await this.prisma.usuario.findUnique({
        where: { id: payload.sub },
      });

      if (!usuario || !usuario.activo) {
        return reply.status(401).send({
          statusCode: 401,
          message: 'Usuario no válido o desactivado',
          timestamp: new Date().toISOString(),
        });
      }

      // Generar nuevo access token
      const newAccessToken = jwtSigner.sign(
        {
          sub: usuario.id,
          email: usuario.email,
          rol: usuario.rol,
        },
        { expiresIn: ACCESS_TOKEN_EXPIRY_SECONDS }
      );

      // [D] PARTE 3.1: RTR — generar nuevo refresh token también
      const newRefreshToken = jwtSigner.sign(
        {
          sub: usuario.id,
          email: usuario.email,
          type: 'refresh',
        },
        { expiresIn: REFRESH_TOKEN_EXPIRY_SECONDS }
      );

      logger.info({ usuarioId: usuario.id }, 'Tokens renovados exitosamente');

      return reply.send({
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      });
    } catch (error: any) {
      logger.error(
        {
          errMessage: error?.message,
          errStack: error?.stack,
        },
        'Error al renovar tokens'
      );
      return reply.status(401).send({
        statusCode: 401,
        message: 'Token inválido o expirado',
        timestamp: new Date().toISOString(),
      });
    }
  }
}

// =============================================================================
// TicoTax SaaS — Zod Schemas (Validaciones)
// Épica TICOTAX-100 | Sprint 3 | Historia TICOTAX-105
//
// [D] Plan Maestro PARTE 3.1: Validación de entrada en todos los endpoints
// Todos los schemas están tipados con TypeScript inference
// =============================================================================

import { z } from 'zod';

// ---------------------------------------------------------------------------
// AUTH SCHEMAS
// ---------------------------------------------------------------------------

export const RegisterSchema = z.object({
  nombre: z.string().min(3).max(100),
  email: z.string().email(),
  password: z.string().min(8).max(128),
  cedula: z.string().optional(),
  rol: z.enum(['ADMIN', 'CONTADOR', 'EMPRESA']).default('EMPRESA'),
});

export type RegisterInput = z.infer<typeof RegisterSchema>;

export const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

export type LoginInput = z.infer<typeof LoginSchema>;

export const RefreshSchema = z.object({
  refreshToken: z.string(),
});

export type RefreshInput = z.infer<typeof RefreshSchema>;

export const AuthResponseSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  usuario: z.object({
    id: z.string(),
    email: z.string(),
    nombre: z.string(),
    rol: z.enum(['ADMIN', 'CONTADOR', 'EMPRESA']),
  }),
});

export type AuthResponse = z.infer<typeof AuthResponseSchema>;

// ---------------------------------------------------------------------------
// USUARIO SCHEMAS
// ---------------------------------------------------------------------------

export const MeResponseSchema = z.object({
  id: z.string(),
  email: z.string(),
  nombre: z.string(),
  rol: z.enum(['ADMIN', 'CONTADOR', 'EMPRESA']),
  cedula: z.string().nullable().optional(),
  activo: z.boolean(),
  emailVerificado: z.boolean(),
  createdAt: z.union([z.string(), z.date()]),
});

export type MeResponse = z.infer<typeof MeResponseSchema>;

// ---------------------------------------------------------------------------
// JWT PAYLOAD SCHEMA
// [D] PARTE 3.1: Estructura del JWT
// ---------------------------------------------------------------------------

export const JwtPayloadSchema = z.object({
  sub: z.string(),        // usuario.id
  email: z.string(),
  rol: z.enum(['ADMIN', 'CONTADOR', 'EMPRESA']),
  iat: z.number(),
  exp: z.number(),
});

export type JwtPayload = z.infer<typeof JwtPayloadSchema>;

// ---------------------------------------------------------------------------
// ERROR RESPONSE SCHEMA
// ---------------------------------------------------------------------------

export const ErrorResponseSchema = z.object({
  statusCode: z.number(),
  message: z.string(),
  timestamp: z.string(),
});

export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

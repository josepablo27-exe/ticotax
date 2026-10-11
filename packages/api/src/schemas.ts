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
// ENTIDAD SCHEMAS
// ---------------------------------------------------------------------------

export const EntidadCreateSchema = z.object({
  nombre: z.string().min(3).max(100),
  cedulaJuridica: z.string().optional(),
  tipoCedula: z.string().optional().nullable(),
  email: z.string().email().optional().nullable().or(z.literal('')),
});

export type EntidadCreateInput = z.infer<typeof EntidadCreateSchema>;

export const EntidadResponseSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  cedulaJuridica: z.string().nullable().optional(),
  tipoCedula: z.string().nullable().optional(),
  email: z.string().nullable().optional(),
  activo: z.boolean(),
  createdAt: z.union([z.string(), z.date()]),
});

export type EntidadResponse = z.infer<typeof EntidadResponseSchema>;

export const EntidadListResponseSchema = z.object({
  data: z.array(EntidadResponseSchema),
  total: z.number(),
  page: z.number(),
  pageSize: z.number(),
});

export type EntidadListResponse = z.infer<typeof EntidadListResponseSchema>;

// ---------------------------------------------------------------------------
// FACTURA SCHEMAS
// ---------------------------------------------------------------------------

const montoNumerico = z.number().or(z.string().transform((val) => parseFloat(val)));

export const FacturaCreateSchema = z
  .object({
    entidadId: z.string().uuid(),
    claveHacienda: z.string().length(50).optional(),
    numeroConsecutivo: z.string().optional(),
    tipoDocumento: z.string().default('FE'),
    emisorCedula: z.string().optional(),
    emisorNombre: z.string().optional(),
    receptorCedula: z.string().optional(),
    fechaEmision: z.string().optional(),
    moneda: z.string().default('CRC'),
    // `monto` es el campo que persiste hoy en BD (ver factura.controller.ts).
    // `montoTotal` es el nombre real de Hacienda (facturas.monto_total en
    // init.sql). Se aceptan ambos y `monto` gana si el cliente manda los dos;
    // si solo llega `montoTotal`, se usa como monto efectivo en vez de
    // descartarlo silenciosamente.
    monto: montoNumerico.optional(),
    montoTotal: montoNumerico.optional(),
    montoIva: z.number().or(z.string()).optional(),
    montoExonerado: z.number().or(z.string()).optional(),
    montoExento: z.number().or(z.string()).optional(),
    descripcion: z.string().optional().nullable(),
  })
  .transform((data) => ({
    ...data,
    monto: data.monto ?? data.montoTotal ?? 0,
  }));

export type FacturaCreateInput = z.infer<typeof FacturaCreateSchema>;

export const FacturaResponseSchema = z.object({
  id: z.string(),
  entidadId: z.string().optional(),
  claveHacienda: z.string().nullable().optional(),
  numeroConsecutivo: z.string().nullable().optional(),
  emisorNombre: z.string().nullable().optional(),
  monto: z.number().optional(),
  montoTotal: z.union([z.number(), z.string()]).nullable().optional(),
  moneda: z.string().optional(),
  descripcion: z.string().nullable().optional(),
  estado: z.string(),
  fechaEmision: z.union([z.string(), z.date()]).nullable().optional(),
  createdAt: z.union([z.string(), z.date()]),
});

export type FacturaResponse = z.infer<typeof FacturaResponseSchema>;

export const FacturaListResponseSchema = z.object({
  data: z.array(FacturaResponseSchema),
  total: z.number(),
  page: z.number(),
  pageSize: z.number(),
});

export type FacturaListResponse = z.infer<typeof FacturaListResponseSchema>;

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

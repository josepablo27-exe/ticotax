# Procedencia de las dependencias — TicoTax

**Épica TICOTAX-100 | Historia TICOTAX-102 (Setup del Monorepo y Entorno Local)**

Este documento existe para que cualquier dependencia del proyecto se pueda rastrear
hasta el *TicoTax SaaS — Plan Maestro Definitivo v4.0*, o quede marcada como decisión
del equipo. Es el respaldo de la regla de trabajo "Cero Invenciones".

| Etiqueta | Significado |
|---|---|
| **[D]** | Nombrada textualmente en el Plan Maestro |
| **[D\*]** | La tecnología está documentada pero el nombre exacto del paquete no; ver nota |
| **[X]** | No aparece en el Plan Maestro. Decisión del equipo, con justificación |

Todas las versiones se resolvieron contra los registros reales (npm y PyPI) y quedaron
congeladas en `package-lock.json`. Ningún major contradice la PARTE 2.1.

---

## packages/api — Node.js 24 + Fastify

### Dependencias de ejecución

| Paquete | Rango | Resuelto | Origen |
|---|---|---|---|
| `fastify` | ^4.26.0 | 4.29.1 | **[D]** PARTE 2.1 — "Node.js + TypeScript + Fastify \| 24.x / 4.x" |
| `@prisma/client` | ^5.10.0 | 5.22.0 | **[D]** PARTE 2.1 — "ORM \| Prisma \| 5.x" |
| `zod` | ^3.22.4 | 3.25.76 | **[D]** PARTE 2.1 — "Validación \| Zod (Node) \| 3.x" |
| `pino` | ^8.19.0 | 8.21.0 | **[D]** PARTE 2.1 y PARTE 7.1 — logs JSON a stdout |
| `bcrypt` | ^5.1.1 | — | **[D]** PARTE 4.1 (A02) — `await bcrypt.hash(password, BCRYPT_ROUNDS)` |
| `nodemailer` | ^6.9.11 | — | **[D]** PARTE 3.6 — `import nodemailer from 'nodemailer'` |
| `handlebars` | ^4.7.8 | — | **[D]** PARTE 3.6 — `import Handlebars from 'handlebars'` |
| `date-fns` / `date-fns-tz` | ^3.6.0 / ^3.1.3 | — | **[D]** PARTE 2.1 — "date-fns + date-fns-tz \| 3.x" |
| `@fastify/helmet` | ^11.1.1 | — | **[D\*]** PARTE 2.1 dice "Helmet". Ver *Inconsistencia 1* |
| `@fastify/rate-limit` | ^9.1.0 | 9.1.0 | **[D\*]** PARTE 2.1 dice "express-rate-limit". Ver *Inconsistencia 1* |
| `@fastify/swagger` + `-ui` | ^8.14.0 / ^3.0.0 | 3.1.0 | **[D]** PARTE 2.1 — "Docs API \| Fastify Swagger \| OpenAPI 3.0" |
| `@fastify/multipart` | ^8.1.0 | — | **[X]** El endpoint `POST /facturas/upload` (PARTE 9) sube archivos XML; Fastify no parsea multipart sin este plugin |
| `ioredis` | ^5.3.2 | — | **[X]** PARTE 2.1 exige Redis 7 pero no nombra el cliente de Node |
| `prom-client` | ^15.1.0 | 15.1.3 | **[X]** PARTE 7.2 usa `new Counter({...})` y `new Histogram({...})` sin decir de qué librería |
| `@sentry/node` | ^7.107.0 | 7.120.4 | **[X]** PARTE 2.1 nombra "Sentry"; el paquete concreto es inferencia |
| `@aws-sdk/client-s3` | ^3.535.0 | — | **[X]** PARTE 2.1 exige S3 y `facturas.s3_key` lo referencia, pero no se nombra SDK |

### Dependencias de desarrollo

| Paquete | Origen |
|---|---|
| `typescript` ^5.4 | **[D]** PARTE 2.1 — "Node.js 24 + React + TypeScript + Vite \| 18.x / 5.x" |
| `prisma` ^5.10 | **[D]** CLI de migraciones, PARTE 5.2 |
| `pino-pretty` ^11 | **[D]** PARTE 7.1 — "En desarrollo: pino-pretty lo formatea legible con colores" |
| `jest`, `supertest` | **[D]** PARTE 2.1 — "Testing \| Jest + Supertest + Playwright" |
| `tsx`, `ts-jest`, `@types/*` | **[X]** Herramientas de build/tipado, sin equivalente documentado |

---

## packages/frontend — React 18 + Vite

| Paquete | Rango | Resuelto | Origen |
|---|---|---|---|
| `react` / `react-dom` | ^18.2.0 | 18.3.1 | **[D]** PARTE 2.1 — "React + TypeScript + Vite \| 18.x / 5.x" |
| `vite` | ^5.2.0 | 5.4.21 | **[D]** ídem |
| `@tanstack/react-query` | ^5.28.0 | 5.103.1 | **[D]** PARTE 2.1 — "Estado servidor \| TanStack Query \| 5.x" |
| `@tanstack/react-virtual` | ^3.2.0 | — | **[D]** PARTE 6 — `import { useVirtualizer } from '@tanstack/react-virtual'` |
| `zustand` | ^4.5.2 | 4.5.7 | **[D]** PARTE 2.1 — "Estado cliente \| Zustand \| 4.x" |
| `react-hook-form` | ^7.51.0 | — | **[D]** PARTE 2.1 — "Forms \| React Hook Form + Zod \| 7.x / 3.x" |
| `zod` | ^3.22.4 | — | **[D]** ídem |
| `leaflet` | ^1.9.4 | 1.9.4 | **[D]** PARTE 2.1 — "Mapas \| Leaflet + react-leaflet \| 1.9.x" |
| `react-leaflet` | ^4.2.1 | 4.2.1 | **[D\*]** El "1.9.x" de la tabla es la versión de Leaflet, no la de react-leaflet |
| `recharts` | ^2.12.0 | 2.15.4 | **[D]** PARTE 2.1 — "Gráficos \| Recharts \| 2.x" |
| `date-fns` / `date-fns-tz` | ^3.6.0 / ^3.1.3 | — | **[D]** PARTE 2.1 — 3.x |
| `dompurify` | ^3.0.10 | — | **[D]** PARTE 4.1 (A03) — "XSS: DOMPurify en React para todo contenido externo" |
| `tailwindcss` | ^3.4.1 | 3.4.19 | **[D]** PARTE 2.1 — "Tailwind CSS + shadcn/ui \| 3.x" |
| `vite-plugin-pwa` | ^0.19.0 | 0.19.8 | **[D\*]** PARTE 2.1 dice "7.x". Ver *Inconsistencia 2* |
| `workbox-window` | ^7.0.0 | 7.4.1 | **[D]** PARTE 2.1 — "Workbox \| 7.x" |
| `jest-axe` | ^8.0.0 | 8.0.0 | **[D]** PARTE 6.1 — `import { axe, toHaveNoViolations } from 'jest-axe'` |
| `@playwright/test` | ^1.42.0 | 1.63.0 | **[D]** PARTE 9 — `import { test, expect } from '@playwright/test'` |
| `@sentry/react` | ^7.107.0 | — | **[X]** PARTE 2.1 nombra "Sentry"; el paquete concreto es inferencia |
| `@hookform/resolvers` | ^3.3.4 | — | **[X]** Puente obligatorio entre React Hook Form y Zod |
| `@vitejs/plugin-react` | ^4.2.1 | — | **[X]** PARTE 6 lo importa en `vite.config.ts` pero no lo lista en la tabla de stack |
| `postcss`, `autoprefixer` | — | — | **[X]** Requisitos de instalación de Tailwind 3 |
| `@testing-library/react`, `jest-environment-jsdom`, `@types/*` | — | — | **[X]** Implicados por `render(<FacturaList />)` en PARTE 6.1 |

### shadcn/ui

PARTE 2.1 lo lista como parte del stack de estilos, pero **shadcn/ui no es una dependencia npm**:
es un CLI que copia el código fuente de cada componente dentro del repositorio. Por eso no aparece
en `package.json`. Sus dependencias (`@radix-ui/*`, `class-variance-authority`, `clsx`,
`tailwind-merge`) las agrega el propio CLI cuando se instala cada componente, a partir de
TICOTAX-203. No las pre-instalé para no meter paquetes que quizá nunca se usen.

---

## packages/parser — Python 3.13 + FastAPI

| Paquete | Versión | Origen |
|---|---|---|
| `fastapi` | 0.115.6 | **[D]** PARTE 2.1 — "Python + FastAPI \| 3.13 / 0.11x" |
| `pydantic` | 2.10.4 | **[D]** PARTE 2.1 — "Validación \| Pydantic (Python)" |
| `uvicorn[standard]` | 0.34.0 | **[X]** FastAPI es un framework ASGI: sin servidor ASGI el proceso no arranca |
| `pydantic-settings` | 2.7.0 | **[X]** Factor III exige config 100% por variables de entorno |

### Huecos declarados (se resuelven en TICOTAX-202)

El Plan Maestro describe tres capacidades del parser sin nombrar ninguna librería.
Quedan sin elegir a propósito:

1. **Validación XSD del XML v4.3 de Hacienda** — evidencia: `XSDValidationError ... at validateXSD (parser.py:45)` (PARTE 7.1).
2. **Verificación de firma digital** — evidencia: mensaje `firmaInvalida` (PARTE 6.2) y el fixture `tests/fixtures/factura-firma-invalida.xml` (PARTE 9).
3. **Cliente HTTP hacia el BCCR** — evidencia: "El parser Python llama al BCCR" (PARTE 4.1, A10). El Plan Maestro muestra el guard anti-SSRF en TypeScript con `fetch()`, no su equivalente Python.

---

## Inconsistencias detectadas en el Plan Maestro v4.0

### Inconsistencia 1 — `express-rate-limit` sobre Fastify

PARTE 2.1, fila *Seguridad*: **"Helmet + express-rate-limit"**. Pero la fila *Backend API*
de esa misma tabla define Fastify, no Express. `express-rate-limit` es middleware de Express
y no es compatible con el ciclo de vida de hooks de Fastify.

El mismo cruce aparece en PARTE 4.1 (A01): el middleware `verifyEntityOwnership` usa la firma
de Express (`req, res, next` y `res.status(403).json(...)`), no la de Fastify
(`request, reply` y `reply.code(403).send(...)`).

**Resuelto como:** `@fastify/helmet` + `@fastify/rate-limit`, que son los puertos oficiales
y entregan lo que el documento pide en sustancia — los 15 security headers y el rate limiting
por ventana deslizante de PARTE 4.1 (A04). **Confirmar con el profesor.**

### Inconsistencia 2 — `vite-plugin-pwa 7.x` no existe

PARTE 2.1, fila *PWA*: **"Workbox + vite-plugin-pwa | 7.x"**. `vite-plugin-pwa` nunca ha
publicado una versión 7: su numeración va por `0.x` (la serie actual es `0.19`–`0.21`).
El "7.x" corresponde a **Workbox**, que sí va en 7.x y es la otra mitad de esa misma celda.

**Resuelto como:** `vite-plugin-pwa@^0.19.0` + `workbox-window@^7.0.0`.

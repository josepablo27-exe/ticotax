# TicoTax

SaaS cloud-native para automatizar la gestión de facturas electrónicas de Hacienda (Costa Rica).
Proyecto del curso Desarrollo de Aplicaciones para la Computación en la Nube, ULACIT.

## Estructura del monorepo

```
docs/diagramas/      Diagramas C4, ER y de flujo
infra/postgres/      Esquema PostgreSQL (init.sql)
infra/terraform/     Infraestructura como código (AWS)
packages/api/        API Gateway — Node.js 24 + Fastify + Prisma
packages/parser/     Microservicio de XML — Python 3.13 + FastAPI
packages/frontend/   PWA — React 18 + Vite + Tailwind
```

Las reglas de trabajo del equipo están en [ESTRATEGIA-REPOSITORIO.md](ESTRATEGIA-REPOSITORIO.md) y el backlog en el
Project de GitHub. La guía completa de arranque local se agrega junto con los servicios de la
aplicación en `docker-compose.yml`.

-- =============================================================================
-- TicoTax SaaS — init.sql (esquema base)
-- Épica TICOTAX-100 | Sprint 2 (Semanas 3 y 4) | Historia TICOTAX-104
-- DoD cubierto: "Esquema PostgreSQL creado con pgcrypto y pg_trgm"
--
-- FUENTE ÚNICA: "TicoTax SaaS — Plan Maestro Definitivo v4.0"
--               PARTE 5 — OPTIMIZACIÓN DE BASE DE DATOS
--               Sección 5.1 "Schema PostgreSQL optimizado completo" (págs. 22-25)
--
-- Motor: PostgreSQL 15.x (PARTE 2.1 — "BD principal | PostgreSQL | 15.x")
-- =============================================================================
--
-- ⚠ LEER ANTES DE EJECUTAR — 3 puntos que el Plan Maestro NO resuelve:
--
--   [B1] RESUELTO POR EXTRAPOLACIÓN AUTORIZADA (decisión del equipo).
--        Las tablas `entidades` y `vinculos_contables` NO tienen DDL en el
--        Plan Maestro, pero `facturas.entidad_id` las necesita. Se derivan de
--        las columnas visibles en PARTE 4.1 (OWASP A01) y PARTE 3.1 (Decisión 4).
--        Cada columna va etiquetada [D] / [C] / [X]. Ver sección 3.5 y 3.6.
--
--   [B2] `email CITEXT` requiere la extensión `citext`, que no aparece en la
--        lista de extensiones de 5.1. El propio documento lo advierte:
--        "CITEXT requiere la extensión pero hace el UNIQUE email
--         case-insensitive sin función". Se agrega por exigencia del documento.
--
--   [B3] Los índices Pattern 3 y Pattern 5 usan `unaccent()` y
--        `date_trunc(text, TIMESTAMPTZ)`, que PostgreSQL clasifica como STABLE,
--        no IMMUTABLE. Tal cual están escritos en el documento, PostgreSQL 15
--        los rechaza con:
--          ERROR: functions in index expression must be marked IMMUTABLE
--        → Se envuelven en funciones IMMUTABLE. No se altera ningún campo,
--          ni el patrón de acceso, ni el tipo de índice declarado.
-- =============================================================================


-- =============================================================================
-- 1. EXTENSIONES REQUERIDAS  [Plan Maestro 5.1, pág. 23]
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- DoD TICOTAX-104 + OWASP A02 (pgp_sym_encrypt)
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- Para búsqueda full-text eficiente / DoD TICOTAX-104
CREATE EXTENSION IF NOT EXISTS "unaccent";   -- Búsqueda sin acentos (español)

-- [B2] Exigida por el comentario del propio Plan Maestro sobre usuarios.email.
CREATE EXTENSION IF NOT EXISTS "citext";


-- =============================================================================
-- 2. TABLA usuarios CON ÍNDICES ESTRATÉGICOS  [Plan Maestro 5.1, pág. 23]
-- =============================================================================

CREATE TABLE usuarios (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre            TEXT        NOT NULL CHECK (char_length(nombre) BETWEEN 3 AND 100),
    email             CITEXT      NOT NULL,            -- CITEXT: case-insensitive automático
    password_hash     TEXT        NOT NULL,
    rol               TEXT        NOT NULL CHECK (rol IN ('ADMIN','CONTADOR','EMPRESA')),
    cedula            TEXT,
    telefono          TEXT,
    activo            BOOLEAN     NOT NULL DEFAULT true,
    email_verificado  BOOLEAN     NOT NULL DEFAULT false,
    ultimo_acceso     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Requisito del sílabo "Decisiones": el CHECK de `rol` es la decisión lógica
-- que habilita la bifurcación ADMIN / CONTADOR / EMPRESA usada por el
-- middleware verifyEntityOwnership (OWASP A01, PARTE 4.1).
-- Regla de negocio TicoTax: `password_hash` nunca guarda texto plano —
-- bcrypt con BCRYPT_ROUNDS=12 (PARTE 4.1, A02).

-- CITEXT requiere la extensión pero hace el UNIQUE email case-insensitive sin función
CREATE UNIQUE INDEX idx_usuarios_email      ON usuarios(email);
CREATE INDEX        idx_usuarios_rol_activo ON usuarios(rol) WHERE activo = true;


-- =============================================================================
-- 3. TRIGGER updated_at AUTOMÁTICO  [Plan Maestro 5.1, pág. 23]
-- =============================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_usuarios_updated_at
BEFORE UPDATE ON usuarios
FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- #############################################################################
-- #                                                                           #
-- #   ⚠⚠  ZONA DE EXTRAPOLACIÓN — NO PROVIENE DEL PLAN MAESTRO v4.0  ⚠⚠      #
-- #                                                                           #
-- #   Las secciones 3.5 y 3.6 NO están en el documento base. Se construyen    #
-- #   por ingeniería inversa a partir de las referencias que el Plan Maestro  #
-- #   hace a estas tablas sin publicar su DDL.                                #
-- #                                                                           #
-- #   LEYENDA DE PROCEDENCIA — obligatoria para la defensa académica:         #
-- #     [D] DOCUMENTADO  — la columna/valor aparece textualmente en el PDF.   #
-- #     [C] CONVENCIÓN   — replica un patrón que el propio Plan Maestro usa   #
-- #                        en `usuarios` y `facturas` (PARTE 5.1).            #
-- #     [X] EXTRAPOLADO  — NO está en el PDF. Es una inferencia de diseño y   #
-- #                        debe validarse con el profesor / la organización.  #
-- #                                                                           #
-- #############################################################################


-- =============================================================================
-- 3.5 TABLA entidades  — [EXTRAPOLADA]
--
-- Evidencia documental disponible:
--   · PARTE 5.1 (pág. 23): facturas.entidad_id UUID NOT NULL REFERENCES entidades(id)
--   · PARTE 4.1 (OWASP A01): SELECT 1 FROM entidades e ... WHERE e.id = $1
--                            AND ( e.owner_id = $2 -- es el dueño ... )
--   · PARTE 3.4: endpoint GET /entidades/:id/proveedores/geo
--   · PARTE 9  : el test lee loginRes.body.user.entidades[0].id
--                -> un usuario puede tener N entidades
-- =============================================================================

CREATE TABLE entidades (
    -- [D] Tipo y nombre forzados por el FK de `facturas` (UUID) y por `e.id`.
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- [D] `e.owner_id = $2` donde $2 = req.user.id -> apunta a usuarios(id).
    --     El Plan Maestro no declara la acción ON DELETE; se omite a propósito
    --     (RESTRICT por defecto) para no borrar historial fiscal por cascada.
    owner_id        UUID        NOT NULL REFERENCES usuarios(id),

    -- [X] NO documentada. Justificación: `facturas.receptor_cedula` (5.1) guarda
    --     la cédula del receptor, que es esta entidad. Sin esta columna no se
    --     puede enlazar una factura recibida con su entidad destinataria.
    cedula_juridica TEXT        NOT NULL,

    -- [X] NO documentada. Justificación: el selector de entidad del frontend
    --     (user.entidades[]) necesita una etiqueta legible. El CHECK replica
    --     el patrón de `usuarios.nombre` (PARTE 5.1).
    nombre          TEXT        NOT NULL CHECK (char_length(nombre) BETWEEN 3 AND 100),

    -- [X] NO documentada. Replica el patrón `usuarios.activo` para soportar
    --     baja lógica en vez de DELETE (el historial fiscal no se borra).
    activo          BOOLEAN     NOT NULL DEFAULT true,

    -- [C] Convención del Plan Maestro: ambas tablas de 5.1 llevan este par.
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- [X] NO documentada. En Costa Rica la cédula jurídica es identificador
    --     único ante Hacienda; sin esto se duplicarían entidades.
    CONSTRAINT uq_entidades_cedula UNIQUE (cedula_juridica)
);

-- [D] Access pattern documentado: el middleware verifyEntityOwnership (4.1)
--     filtra por `e.owner_id = $2` en CADA request autenticada. B-Tree parcial
--     siguiendo el mismo criterio que idx_usuarios_rol_activo (5.1).
CREATE INDEX idx_entidades_owner ON entidades (owner_id) WHERE activo = true;

-- [C] Reutiliza la función update_updated_at() declarada en 5.1 (pág. 23).
--     El Plan Maestro solo declara el trigger sobre `usuarios`; extenderlo es
--     convención, no invención de lógica nueva.
CREATE TRIGGER trg_entidades_updated_at
BEFORE UPDATE ON entidades
FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- =============================================================================
-- 3.6 TABLA vinculos_contables  — [EXTRAPOLADA]
--
-- Evidencia documental disponible:
--   · PARTE 4.1 (OWASP A01):
--       LEFT JOIN vinculos_contables vc
--         ON vc.entidad_id = e.id AND vc.contador_id = $2
--       ... OR (vc.estado IN ('ACTIVO','EN_DISPUTA','EN_CIERRE') AND $3 = 'CONTADOR')
--   · PARTE 3.1 (Decisión 4 — "Decisión de acceso RLS según estado del vínculo"):
--       const puedeEditar = vinculo.estado === 'ACTIVO';
--       const puedeLeer   = ['ACTIVO','EN_DISPUTA','EN_CIERRE'].includes(vinculo.estado);
--
-- Semántica: relación N:M entre un usuario con rol CONTADOR y una entidad.
-- Requisito del sílabo "Decisiones": esta tabla es la que alimenta la Decisión 4.
-- =============================================================================

CREATE TABLE vinculos_contables (
    -- [C] PK sustituta UUID, mismo patrón que las dos tablas de 5.1.
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- [D] `vc.entidad_id = e.id`
    --     [X] ON DELETE CASCADE: si se elimina la entidad el vínculo pierde
    --         sentido. El Plan Maestro no especifica la acción referencial.
    entidad_id   UUID        NOT NULL REFERENCES entidades(id) ON DELETE CASCADE,

    -- [D] `vc.contador_id = $2` donde $2 = req.user.id -> usuarios(id).
    contador_id  UUID        NOT NULL REFERENCES usuarios(id),

    -- [D] Los TRES valores del CHECK son textuales del Plan Maestro.
    --     ⚠ VER NOTA ABIERTA abajo: probablemente falten estados.
    estado       TEXT        NOT NULL CHECK (estado IN ('ACTIVO','EN_DISPUTA','EN_CIERRE')),

    -- [C] Par de auditoría, convención de 5.1.
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- [X] NO documentada. Un contador no debería tener dos vínculos vivos con
    --     la misma entidad; además este UNIQUE crea el índice compuesto que
    --     resuelve el LEFT JOIN de OWASP A01 sin scan adicional.
    CONSTRAINT uq_vinculo_entidad_contador UNIQUE (entidad_id, contador_id)
);

-- [X] NO documentado como access pattern explícito, pero lo exige la pantalla
--     "mis entidades" del contador y el Pattern 5 de facturas
--     (idx_facturas_contador_periodo, 5.1) que agrupa trabajo por contador.
CREATE INDEX idx_vinculos_contador ON vinculos_contables (contador_id, estado);

-- [C] Trigger de updated_at, misma función de 5.1.
CREATE TRIGGER trg_vinculos_updated_at
BEFORE UPDATE ON vinculos_contables
FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- -----------------------------------------------------------------------------
-- ⚠ NOTA ABIERTA — INCONSISTENCIA DETECTADA EN EL PLAN MAESTRO
--
-- El CHECK de arriba solo admite los 3 estados que el documento nombra. Pero si
-- esos 3 son los ÚNICOS posibles, entonces la Decisión 4 de PARTE 3.1:
--     puedeLeer = ['ACTIVO','EN_DISPUTA','EN_CIERRE'].includes(vinculo.estado)
-- siempre evalúa a `true` y deja de ser una decisión.
--
-- Eso implica que DEBEN existir estados adicionales (p. ej. uno de revocación o
-- uno pendiente de aceptación) que el Plan Maestro no publica. NO los inventé.
-- Mientras no se confirmen, este CHECK es deliberadamente restrictivo.
-- -----------------------------------------------------------------------------

-- #############################################################################
-- #                     FIN DE LA ZONA DE EXTRAPOLACIÓN                       #
-- #   A partir de aquí se retoma la transcripción literal de PARTE 5.1.       #
-- #############################################################################


-- =============================================================================
-- 4. TABLA facturas CON ÍNDICES PARA TODOS LOS ACCESS PATTERNS
--    [Plan Maestro 5.1, págs. 23-24]
-- =============================================================================

CREATE TABLE facturas (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    entidad_id           UUID        NOT NULL REFERENCES entidades(id),   -- [B1] ya resuelto (sec. 3.5)
    clave_hacienda       CHAR(50)    NOT NULL,
    xml_content_hash     CHAR(64)    NOT NULL,
    numero_consecutivo   TEXT        NOT NULL,
    tipo_documento       TEXT        NOT NULL DEFAULT 'FE',
    emisor_cedula        TEXT        NOT NULL,
    emisor_nombre        TEXT        NOT NULL,
    receptor_cedula      TEXT        NOT NULL,
    fecha_emision        TIMESTAMPTZ NOT NULL,
    fecha_ingestion      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    moneda               CHAR(3)     NOT NULL DEFAULT 'CRC',
    tipo_cambio          NUMERIC(10,4),
    monto_total          NUMERIC(18,5) NOT NULL,
    monto_total_colones  NUMERIC(18,5),
    monto_iva            NUMERIC(18,5) NOT NULL DEFAULT 0,
    monto_exonerado      NUMERIC(18,5) NOT NULL DEFAULT 0,
    monto_exento         NUMERIC(18,5) NOT NULL DEFAULT 0,
    estado               TEXT        NOT NULL DEFAULT 'PENDIENTE'
                                     CHECK (estado IN ('PENDIENTE','PROCESADA','RECHAZADA','REVISION')),
    motivo_rechazo       TEXT,
    s3_key               TEXT        NOT NULL,
    processing_attempts  INT         NOT NULL DEFAULT 1,
    procesada_por        UUID        REFERENCES usuarios(id),
    notas_contador       TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_clave_hacienda    UNIQUE (clave_hacienda),
    CONSTRAINT chk_montos_positivos CHECK (monto_total >= 0 AND monto_iva >= 0)
);

-- Regla de negocio TicoTax — idempotencia: `uq_clave_hacienda` es el mecanismo
-- de deduplicación de facturas electrónicas de Hacienda (Pattern 4, pág. 24).
-- Requisito del sílabo "Decisiones": el CHECK de `estado` define la máquina de
-- estados PENDIENTE -> PROCESADA | RECHAZADA | REVISION que consume el parser
-- Python (TICOTAX-202) y el dashboard fiscal.
-- Nota: el Plan Maestro NO declara trigger `updated_at` sobre `facturas`
-- (solo sobre `usuarios`). No lo agrego por regla de Cero Invenciones.


-- =============================================================================
-- 5. ÍNDICES PARA TODOS LOS ACCESS PATTERNS IDENTIFICADOS CON EXPLAIN ANALYZE
--    [Plan Maestro 5.1, pág. 24]
-- =============================================================================

-- Pattern 1: Listado paginado por entidad y estado (más frecuente)  — B-Tree
CREATE INDEX CONCURRENTLY idx_facturas_paginacion
    ON facturas (entidad_id, estado, id DESC);

-- Pattern 2: Dashboard fiscal — suma de IVA del período  — B-Tree parcial
CREATE INDEX CONCURRENTLY idx_facturas_dashboard
    ON facturas (entidad_id, fecha_emision DESC)
    WHERE estado = 'PROCESADA';

-- ---------------------------------------------------------------------------
-- [B3] Wrapper IMMUTABLE para unaccent().
-- El documento escribe: GIN (unaccent(emisor_nombre) gin_trgm_ops)
-- unaccent() es STABLE (depende del diccionario de la sesión) -> PostgreSQL 15
-- rechaza la expresión en un índice. Se fija el diccionario explícitamente.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f_unaccent(TEXT)
RETURNS TEXT AS $$
    SELECT public.unaccent('public.unaccent'::regdictionary, $1)
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT;

-- Pattern 3: Búsqueda por nombre de emisor (full-text)  — GIN + pg_trgm
CREATE INDEX CONCURRENTLY idx_facturas_emisor_trgm
    ON facturas USING GIN (f_unaccent(emisor_nombre) gin_trgm_ops);
-- Consulta que lo aprovecha:
--   WHERE f_unaccent(emisor_nombre) ILIKE f_unaccent('%' || $1 || '%')

-- Pattern 4: Deduplicación (lookup por clave)
-- Ya cubierto por UNIQUE (clave_hacienda)

-- ---------------------------------------------------------------------------
-- [B3] Wrapper IMMUTABLE para date_trunc sobre TIMESTAMPTZ.
-- El documento escribe: (procesada_por, date_trunc('month', fecha_emision))
-- date_trunc(text, TIMESTAMPTZ) es STABLE (depende del GUC TimeZone).
-- Se ancla a America/Costa_Rica, que es el CR_TIMEZONE del ConfigMap (PARTE 8.2).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION f_mes_emision(TIMESTAMPTZ)
RETURNS DATE AS $$
    SELECT date_trunc('month', $1 AT TIME ZONE 'America/Costa_Rica')::DATE
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT;

-- Pattern 5: Reporte mensual por contador  — B-Tree parcial sobre expresión
CREATE INDEX CONCURRENTLY idx_facturas_contador_periodo
    ON facturas (procesada_por, f_mes_emision(fecha_emision))
    WHERE procesada_por IS NOT NULL;


-- =============================================================================
-- NOTA sobre CREATE INDEX CONCURRENTLY
-- CONCURRENTLY no puede ejecutarse dentro de un bloque de transacción.
-- · Funciona OK vía /docker-entrypoint-initdb.d (psql en autocommit).
-- · FALLA si se ejecuta con `psql --single-transaction` o dentro de una
--   migración Prisma envuelta en transacción. Ver Plan Maestro 5.2
--   ("CONCURRENTLY para índices: nunca bloquea la tabla").
--
-- FUERA DE ALCANCE DE ESTE ARCHIVO (sí están en 5.1, pág. 25, pero no los
-- pediste en esta iteración): MATERIALIZED VIEW mv_proyeccion_fiscal +
-- idx_mv_proyeccion. Pedímelos y los agrego.
-- =============================================================================

"""
TicoTax — Microservicio Parser (FastAPI)
Épica TICOTAX-100 | Sprint 1 (Semanas 1-2) | Historia TICOTAX-102

Código MÍNIMO para que el contenedor levante.
DoD cubierto (TICOTAX-102): "Entorno local funcional con Docker Compose"

Factor IX (Disposability): Graceful shutdown en SIGTERM.
Factor VII (Port binding): Uvicorn escucha en puerto 8000.
Factor XI (Logs): stdout con JSON estructurado, sin archivos de log.

PARTE 8.3 + PARTE 2.2:
  El parser es un microservicio Python/FastAPI que valida XMLs de Hacienda.
  En desarrollo, sirve healthchecks y espera llamadas del API (TICOTAX-202).
"""

import asyncio
import logging
import signal
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import AsyncGenerator

from fastapi import FastAPI, Response, status
from fastapi.responses import JSONResponse
import uvicorn

# ============================================================================
# Configuración
# ============================================================================

PORT = 8000
HOST = "0.0.0.0"

# ============================================================================
# Logging JSON estructurado (Factor XI)
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='{"level":"%(levelname)s","message":"%(message)s","timestamp":"%(asctime)s","logger":"%(name)s"}',
    datefmt='%Y-%m-%dT%H:%M:%SZ',
    handlers=[
        logging.StreamHandler(sys.stdout)  # stdout, no stderr (compatible con Docker logs)
    ]
)
logger = logging.getLogger(__name__)

# ============================================================================
# Estado global
# ============================================================================

class AppState:
    """Mantiene el estado de la aplicación para healthchecks."""

    def __init__(self):
        self.is_ready = False
        self.is_shutting_down = False


app_state = AppState()


# ============================================================================
# Lifespan context manager (FastAPI 0.93+)
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """
    Maneja startup y shutdown de la aplicación.
    Factor IX (Disposability): graceful shutdown.
    """
    # STARTUP
    logger.info("Parser iniciando...")
    app_state.is_ready = True
    logger.info("✓ Parser ready")

    yield

    # SHUTDOWN
    logger.info("Parser recibió SIGTERM, drenando conexiones...")
    app_state.is_shutting_down = True
    app_state.is_ready = False
    await asyncio.sleep(1)  # Dar tiempo a requests en vuelo
    logger.info("✓ Parser shut down completado")


# ============================================================================
# FastAPI app
# ============================================================================

app = FastAPI(
    title="TicoTax Parser",
    description="Microservicio para procesar XMLs de Hacienda",
    version="0.1.0",
    lifespan=lifespan,
)


# ============================================================================
# Healthchecks (Factor IX: Health checks para orchestrador)
# ============================================================================

@app.get("/health/live", status_code=status.HTTP_200_OK)
async def health_live() -> JSONResponse:
    """
    Liveness probe para Kubernetes/Docker.
    Indica si el contenedor está corriendo.
    """
    return JSONResponse(
        {"status": "live", "timestamp": datetime.now(timezone.utc).isoformat()},
        status_code=status.HTTP_200_OK,
    )


@app.get("/health/ready", status_code=status.HTTP_200_OK)
async def health_ready() -> JSONResponse:
    """
    Readiness probe para Kubernetes/Docker.
    Indica si el servicio está listo para recibir tráfico.
    """
    if not app_state.is_ready:
        return JSONResponse(
            {"status": "not_ready", "reason": "Initializing"},
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    if app_state.is_shutting_down:
        return JSONResponse(
            {"status": "not_ready", "reason": "Shutting down"},
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    return JSONResponse(
        {"status": "ready", "timestamp": datetime.now(timezone.utc).isoformat()},
        status_code=status.HTTP_200_OK,
    )


# ============================================================================
# Rutas
# ============================================================================

@app.get("/", status_code=status.HTTP_200_OK)
async def root() -> JSONResponse:
    """Raíz del parser."""
    return JSONResponse(
        {
            "service": "ticotax-parser",
            "version": "0.1.0",
            "status": "operational",
            "endpoints": {
                "health_live": "/health/live",
                "health_ready": "/health/ready",
            },
        },
        status_code=status.HTTP_200_OK,
    )


# ============================================================================
# Manejo de SIGTERM para graceful shutdown (Factor IX)
# ============================================================================

def signal_handler(signum, frame):
    """Maneja SIGTERM del orchestrador (Docker, K8s, etc.)."""
    logger.info("Señal SIGTERM recibida, iniciando graceful shutdown...")
    sys.exit(0)


# ============================================================================
# Punto de entrada
# ============================================================================

if __name__ == "__main__":
    # Registrar handler para SIGTERM (orchestrador: Docker, K8s, etc.)
    signal.signal(signal.SIGTERM, signal_handler)

    # Logs de inicio (JSON estructurado, compatible con CloudWatch/ELK)
    logger.info(
        f"TicoTax Parser iniciando en http://{HOST}:{PORT}",
        extra={
            "service": "parser",
            "host": HOST,
            "port": PORT,
            "version": "0.1.0"
        }
    )
    logger.info("  GET /health/live   (liveness probe)")
    logger.info("  GET /health/ready  (readiness probe)")
    logger.info("  GET /               (raíz del parser)")

    # Iniciar Uvicorn (ASGI server para FastAPI)
    uvicorn.run(
        "app.main:app",
        host=HOST,
        port=PORT,
        reload=True,  # Hot reload en dev (--reload del script del Dockerfile)
        log_level="info",
    )

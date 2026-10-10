# TicoTax · Estrategia de trabajo en el repositorio

Todo el código entra por Pull Request al repositorio público, y cada tarea del tablero se cierra con su commit.

## Dónde trabajamos

| | |
|---|---|
| Repositorio | [josepablo27-exe/ticotax](https://github.com/josepablo27-exe/ticotax) |
| Tablero | [TicoTax · Backlog](https://github.com/users/josepablo27-exe/projects/3): 18 tareas, Todo → In Progress → Done |
| Rama principal | `main`, protegida: solo entra con PR y 1 aprobación |
| Tipo de merge | Solo *Create a merge commit*, para que cada commit conserve su autor |

Cada integrante debe aceptar la invitación de GitHub (vence en 7 días) y configurar git con el correo de su cuenta.

## Roles y tareas

| Rol | Tareas del tablero |
|---|---|
| Líder Scrum / DevOps | #1 Estructura del repositorio · #5 Compose de datos · #15 Perfil del usuario |
| Arquitectura / Parser | #2 Diagramas C4 y ER · #8 Parser FastAPI · #14 Diagramas de flujo |
| Cloud / IaC | #4 Terraform de red · #9 Servicios AWS · #17 Entidades |
| Base de datos | #3 Esquema PostgreSQL · #7 Modelo Prisma · #18 Facturas |
| Backend API | #6 API base · #11 Autenticación JWT · #12 Compose completo |
| Frontend / PWA | #10 Frontend base · #13 PWA · #16 Manejo de errores |

## Flujo de cada tarea

Solo el commit 1 de P1 va directo a `main`, porque el repositorio está vacío. Todos los demás siguen estos pasos:

1. Mover la tarea a **In Progress** en el tablero.
2. Actualizar y crear la rama:
   ```bash
   git switch main
   git pull origin main
   git switch -c feature/TICOTAX-<id>-<descripcion>
   ```
3. Hacer los cambios de la tarea y revisar con `git status` que solo aparezcan los archivos de la tarea.
4. Hacer el commit y subir la rama:
   ```bash
   git add <archivos>
   git commit -m "<mensaje>"
   git push -u origin <rama>
   ```
5. Abrir el Pull Request con **`Closes #N`** en la descripción (N = número de la tarea) y confirmar que la tarea aparece enlazada en *Development*.
6. Otra persona revisa y aprueba; después se hace **Create a merge commit**.
7. Verificar la tarea en **Done** y actualizar: `git switch main`, `git pull origin main`, `git fetch --prune`.

Si una tarea queda bloqueada, se comenta en su tarjeta del tablero y se avisa en el grupo.

## Orden y reglas contra conflictos

Las tareas se hacen en orden, de la #1 a la #18, y cada una empieza cuando la anterior ya está en `main`. Así se evitan los conflictos de merge.

- **Nunca dos tareas al mismo tiempo sobre el mismo archivo.** Las #15, #17 y #18 modifican `server.ts` y `schemas.ts`: van estrictamente una después de otra.
- **Siempre `git pull origin main` antes de crear la rama**, sobre todo cuando la tarea modifica archivos que ya están en el repositorio.
- **Solo se agregan los archivos de la propia tarea**; si `git status` muestra otros, no se suben.
- El responsable de la tarea siguiente espera el aviso en el grupo de que la anterior quedó en **Done**.

## Convenciones

| Qué | Formato | Ejemplo |
|---|---|---|
| Rama | `feature/TICOTAX-<id>-<descripcion>` | `feature/TICOTAX-105-autenticacion` |
| Commit | `<tipo>(<ámbito>): <descripción> [TICOTAX-<id>]` | `feat(api): autenticación JWT con register, login y refresh [TICOTAX-105]` |
| Pull Request | Primera línea: `Closes #N` | `Closes #11` |

Tipos de commit: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`.

Nunca se suben `.env`, `node_modules/`, `dist/`, `.venv/`, `__pycache__/`, `.DS_Store` ni `terraform.tfvars`; ya están en `.gitignore`.

## Tags y problemas comunes

P1 marca cada avance con un tag sobre `main`, cuando todos sus PRs ya están mergeados: `avance-2` para el Avance 2 y `v1.0-final` para la entrega final.

| Problema | Qué hacer |
|---|---|
| El push falla con *Internal Server Error* | No borrar el commit: esperar unos minutos y repetir solo `git push` |
| Después del merge, la tarea no se cerró | Cerrarla a mano con el comentario `Completada en #<número del PR>` |
| La tarjeta tarda en pasar a Done | Esperar unos segundos y recargar el tablero |
| `git status` muestra archivos que no son de la entrega | No agregarlos; avisar en el grupo |

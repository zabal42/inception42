# Auditoría técnica (solo lectura) — Detalle de RISK

Repositorio auditado: `/home/runner/work/inception42/inception42`  
Alcance: análisis estático, sin modificar archivos, sin acciones destructivas.

## RISK 1 — `srcs/requirements/wordpress/tools/entrypoint.sh:62`

### Qué hace exactamente el código
- Línea analizada: `check_pattern DOMAIN_NAME "$DOMAIN_NAME" '[A-Za-z0-9.-]+'`
- Valida que `DOMAIN_NAME` contenga solo letras, números, `.` y `-`.
- No fuerza que el valor sea exactamente del tipo `<login>.42.fr`.

### Requisito concreto del subject afectado
- Subject Inception v5.2 (copia pública usada como referencia): el dominio operativo debe ser `login.42.fr` (sustituyendo `login` por el login real).

### Cómo se reproduciría el fallo
- Configurar `DOMAIN_NAME=example.com` (u otro dominio válido no `*.42.fr`).
- El patrón de esta línea lo aceptaría.

### Incumplimiento demostrado o mejora
- **RISK**, no **FAIL** demostrado en el despliegue actual.
- Con la evidencia aportada (`mzabal-m.42.fr` verificado en Firefox), el requisito sí se estaría cumpliendo en ejecución real.
- El riesgo es de validación permisiva (permite configuraciones no conformes si alguien cambia `.env`).

### Prueba que lo confirmaría
- Prueba de configuración en entorno de test: arrancar con un `DOMAIN_NAME` no `*.42.fr` y comprobar que WordPress no bloquea por esta validación.

---

## RISK 2 — `srcs/.env.example:5`

### Qué hace exactamente el código
- Línea analizada: `DOMAIN_NAME=CHANGE_ME.42.fr`
- Plantilla orientativa correcta para usar dominio `.42.fr`.
- Al ser ejemplo, no impone por sí sola el valor final en `srcs/.env`.

### Requisito concreto del subject afectado
- Mismo requisito: dominio `login.42.fr`.

### Cómo se reproduciría el fallo
- Copiar `.env.example` a `.env` y luego editar `DOMAIN_NAME` a un FQDN distinto.
- El stack puede seguir siendo técnicamente arrancable si el resto de validaciones lo permite.

### Incumplimiento demostrado o mejora
- **RISK**, no **FAIL** demostrado.
- La plantilla está alineada con el subject; el riesgo existe porque no hay enforcement estricto end-to-end de `<login>.42.fr` en todas las validaciones.

### Prueba que lo confirmaría
- Verificación de `srcs/.env` efectivo en entorno auditado y contraste con el dominio servido.
- En este caso, la evidencia aportada indica dominio operativo correcto (`mzabal-m.42.fr`), por lo que no hay incumplimiento probado.

---

## RISK 3 — `srcs/requirements/mariadb/conf/60-inception.cnf:6`

### Qué hace exactamente el código
- Línea analizada: `bind-address = 0.0.0.0`
- MariaDB escucha en todas las interfaces del contenedor.

### Requisito concreto del subject afectado
- El subject exige comunicación entre contenedores mediante red Docker interna y que NGINX sea el único punto de entrada público por 443.

### Cómo se reproduciría el fallo
- No produce por sí solo exposición pública en host, porque en Compose MariaDB no publica puertos (`ports:` no definido para ese servicio).
- Sí permite que cualquier contenedor conectado a la red `inception` pueda intentar conexión a `mariadb:3306`.

### Incumplimiento demostrado o mejora
- **RISK de hardening interno**, no **FAIL** del subject.
- Dado que WordPress debe conectar por red bridge interna, escuchar fuera de loopback del contenedor es funcionalmente coherente.
- No hay evidencia de exposición externa al host en esta configuración.

### Prueba que lo confirmaría
- Confirmar puertos publicados: `docker compose ... ps` (solo `443` en `nginx`).
- Confirmar alcance interno: prueba TCP desde un contenedor en red `inception` hacia `mariadb:3306`.

---

## Conclusión operativa de estos RISK

- No se identifica **FAIL demostrado** en estos tres puntos con la evidencia actual.
- Riesgos 1 y 2: cumplimiento del dominio depende de configuración efectiva; la instalación auditada reporta `mzabal-m.42.fr` operativo.
- Riesgo 3: punto de hardening interno, compatible con el requisito de comunicación WP↔MariaDB por red bridge.

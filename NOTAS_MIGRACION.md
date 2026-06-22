# Notas de migración — Reporte de Dispersiones Mensuales (SQL Server → Oracle / Bantotal)

Conversión de sintaxis de los 6 queries usados por GoAnywhere MFT para el reporte
de Órdenes de Giro / Dispersiones Mensuales. Versión de origen confirmada por
el usuario: **1_v2**.

## 1. Por qué se eliminan los bloques DECLARE/SET

GoAnywhere MFT ejecuta estos scripts vía JDBC como una única consulta que debe
devolver un `ResultSet`. Un bloque PL/SQL anónimo (`BEGIN...END;`) no devuelve
filas de esa forma. Por eso, en cada uno de los 6 archivos, el bloque
`DECLARE @variable / SET @variable = ...` de T-SQL se reemplazó por una cadena
de CTEs (`WITH base_fechas → dow_calc → holiday_calc → fechas_habiles`) que
calculan exactamente los mismos valores de fecha dentro de un único `SELECT`.

## 2. Confirmación de versión 1_v2 vs 2_v2

El documento `OrdendeGiroReporteDispersionesMensuales.md` describe diferencias
entre las carpetas `1_v2` y `2_v2`. Los 6 archivos `.sql` adjuntos corresponden
a **1_v2**, y la conversión a Oracle se hizo fiel a esa versión:

| Query | 1_v2 (convertido) | 2_v2 (NO incluido, solo referencia) |
| --- | --- | --- |
| TOTAL_DETALLE_DESEMBOLSO | `LEFT JOIN Seguros` + filtro `getdate()-17` | `INNER JOIN Seguros` + filtro `getdate()` (sin -17) |
| TOTAL_DETALLE_GIRO | CORTE DISPERSION `=` | CORTE DISPERSION `>` |
| DETALLE_DESEMBOLSO | CORTE DISPERSION `=`, `ORDER BY 29` | CORTE DISPERSION `>`, `ORDER BY 32` |
| DETALLE_GIRO | CANAL GIRO sin rama "Mantenimiento Prepagado"; fuente `OriginacionPROD_SNAPSHOT` (servidor .41); `IdDesembolsoDetalle IN (1,2,6,7)`; CORTE DISPERSION `=` | CANAL GIRO con rama extra; fuente `OriginacionPROD` (servidor .71, productivo, no snapshot); `IN (1,6,7)`; CORTE DISPERSION `>` |

Si en el futuro se requiere migrar también la variante 2_v2, avisar para generar
esas versiones por separado (no se generaron en esta entrega).

## 3. Servidores enlazados → DB LINK de Oracle

| Origen SQL Server | Destino Oracle asumido |
| --- | --- |
| `[180.26.149.41].[OriginacionPROD_SNAPSHOT].[dbo].tabla` | `originacionprod_snapshot.tabla@dbl_originacionprod_snapshot` |
| `[180.26.149.71].[OriginacionPROD].[dbo].tabla` (solo en 2_v2, no usado aquí) | `originacionprod.tabla@dbl_originacionprod` |

**Pendiente:** el DBA debe confirmar/crear los DB LINK reales en Oracle con esos
nombres (o indicar los nombres reales para reemplazar en los 4 archivos que los
usan: `DETALLE_DESEMBOLSO_ORACLE.sql`, `DETALLE_GIRO_ORACLE.sql`,
`TOTAL_DETALLE_DESEMBOLSO_ORACLE.sql`).

## 4. Bases de datos locales → esquemas Oracle

Se asume que `BDPremierOriginacion`, `BDPremierPrueba`, `BDFinanciera` y
`reportes` pasan a ser esquemas dentro de la misma instancia Oracle (se quitó
el `.dbo.` y se usan en minúsculas: `bdpremieroriginacion`, `bdpremierprueba`,
`bdfinanciera`, `reportes`). **Esto requiere confirmación del equipo de
migración a Bantotal**, ya que tablas de origen como `Desembolso`,
`DesembolsoRelacion`, `DiasFestivos`, `Banco`, etc. probablemente no existen
de forma nativa en Bantotal y son parte de un ejercicio de mapeo de datos más
amplio que excede el alcance de esta sola tarea de traducción de sintaxis.

## 5. Quirks del negocio que se preservaron tal cual (no se corrigieron)

- **Chequeo de festivos con la fecha de HOY en vez de la fecha ancla del mes:**
  en las dos primeras ramas de cada `CASE` de "día hábil" (en los 5 queries que
  calculan fechas), el SQL Server original consulta `DiasFestivos` usando
  `getdate()+N` / `getdate()-N` (la fecha de hoy) en lugar de
  `@DiaIniMes+N` / `@DiaFinMes-N` (la fecha ancla del mes). Esta inconsistencia
  se tradujo literalmente (usando `hoy+N` en las CTEs) sin corregirla, porque
  la tarea solicitada es traducción de sintaxis, no corrección de lógica de
  negocio. Validar con el negocio si es intencional.
- **`getdate()-17`** en `TOTAL_DETALLE_DESEMBOLSO` (1_v2): se preservó como
  `fh.hoy - 17`.
- **`ORDER BY 29`** en `DETALLE_DESEMBOLSO` y **`ORDER BY 10`** en
  `DETALLE_GIRO`: aunque el SELECT final tiene más columnas (32 y 10
  respectivamente — en este caso coinciden, pero en DETALLE_DESEMBOLSO el
  SELECT tiene 32 columnas y el ORDER BY apunta a la columna 29, no a la 32),
  se preservó el ordinal exacto del original sin "corregirlo" a la última
  columna.
- **`TOTAL_DETALLE_GIRO`**: la columna `[CORTE DISPERSION]` está comentada en
  el SELECT original (solo se usa en el WHERE); por eso el SELECT final en
  Oracle tiene 7 columnas, no 8.

## 6. Funciones de usuario recreadas (ver `HELPER_FUNCTIONS_ORACLE.sql`)

- **`bdpremierprueba.dbo.FormatMoney(valor, longitud, prefijo, sufijo, sep_decimal, sep_miles)`**:
  en los 6 queries siempre se invoca como `FormatMoney(valor,30,'','',',','')`.
  Se determinó que el 5to parámetro es el separador **decimal** (no el de
  miles) porque varias fórmulas comparan el resultado contra el literal
  `' - $0,00'` (coma como separador decimal). Recreada en Oracle usando
  `TO_CHAR(...,'FM999G999G999G999G990D00', 'NLS_NUMERIC_CHARACTERS=...')`.
  **No se tuvo acceso a la función original; validar la salida contra casos
  reales antes de producción** (NULL, cero, negativos, valores grandes).
- **`bdpremierprueba.dbo.Format_Number(valor, mascara, longitud, decimales)`**:
  el único uso real es `Format_Number(pla.Cuotas,'',3,0)` (entero relleno con
  ceros a 3 posiciones). Se recreó cubriendo ese caso; el comportamiento de
  `mascara` y de `decimales > 0` es una aproximación no validada.
- **`BDPremierPrueba.dbo.Format_DateToString('AAMMDD', fecha)`**: NO se
  recreó como función — se reemplazó en línea por `TO_CHAR(fecha,'YYMMDD')`
  en los 3 queries que la usan, porque en todos los casos se invoca solo con
  esa máscara fija.

**Importante:** `HELPER_FUNCTIONS_ORACLE.sql` debe ejecutarse (crear las
funciones) ANTES de ejecutar cualquiera de los 6 reportes, ya que estos las
referencian directamente.

## 7. Supuestos sobre columnas sin calificar (sin alias de tabla) en el SQL original

- En `DETALLE_GIRO`: `numeroCuenta` y `tipoCuenta` (rama ELSE de los CASE) se
  asumieron como columnas de `BDPremierOriginacion.dbo.DesembolsoRelacion`
  (alias `dre`), por ser la única tabla del query relacionada con datos
  bancarios del giro.
- También en `DETALLE_GIRO`: `ope.OperacionCancelarPM`, `OperacionaCancelarPM2`,
  `OperacionaCancelarPM3`, `valorcruce1`, `valorcruce2`, `valorcruce3` (primera
  rama del CASE de NUMEROCUENTA, caso sin fila en InformacionPM) se asumieron
  columnas de `Operaciones` (alias `ope`), ya que `ope.OperacionCancelarPM` se
  referencia explícitamente así en el original. Se preservó la falta de alias
  exactamente como en el SQL Server original (no se agregaron calificadores
  que no estaban).
- En los queries de totales y detalle: `IdDesembolsoDetalle` / `fechaenvio`
  (sin alias en el WHERE original) se asumieron como columnas de
  `DesembolsoRelacion` (alias `dre`), consistente con su uso calificado en
  otras partes del mismo query.

## 8. Comportamiento de Oracle a validar con GoAnywhere

- En `TOTAL_DETALLE_DESEMBOLSO_ORACLE.sql` y `TOTAL_DETALLE_GIRO_ORACLE.sql`,
  varias columnas de salida son literales `''` (marcador de columna no usada
  en el reporte). **En Oracle, `''` se evalúa como `NULL`**, a diferencia de
  SQL Server donde `''` es una cadena vacía real. Si el archivo plano que
  genera GoAnywhere distingue entre celda vacía y celda nula (por ejemplo en
  un CSV con o sin comillas), validar el resultado y, de ser necesario,
  ajustar la plantilla de salida de GoAnywhere (esto no se puede resolver
  solo con sintaxis SQL).

## 9. Archivos entregados — versión 1_v2

- `FECHA_INICIO_MES_ORACLE.sql`
- `FECHA_FIN_MES_ORACLE.sql`
- `DETALLE_DESEMBOLSO_ORACLE.sql`
- `DETALLE_GIRO_ORACLE.sql`
- `TOTAL_DETALLE_DESEMBOLSO_ORACLE.sql`
- `TOTAL_DETALLE_GIRO_ORACLE.sql`
- `HELPER_FUNCTIONS_ORACLE.sql` (ejecutar primero)
- `NOTAS_MIGRACION.md` (este archivo)

## 10. Archivos entregados — versión 2_v2

Misma lógica de negocio que 1_v2, con las diferencias puntuales descritas en
la sección 2 de este documento (y detalladas también en el encabezado de cada
archivo `_2V2`):

- `FECHA_INICIO_MES_ORACLE_2V2.sql` — idéntico a la versión 1_v2.
- `FECHA_FIN_MES_ORACLE_2V2.sql` — idéntico a la versión 1_v2.
- `DETALLE_DESEMBOLSO_ORACLE_2V2.sql` — cambia `=` por `>` en el filtro de
  CORTE DISPERSION y el `ORDER BY` de 29 a 32 (ahora sí apunta a la columna
  real CORTE DISPERSION, la última del SELECT).
- `DETALLE_GIRO_ORACLE_2V2.sql` — las tablas derivadas PM1..PM10
  (InformacionPM) ahora leen desde `originacionprod.tabla@dbl_originacionprod`
  (servidor productivo .71, NO snapshot) en vez del DB LINK de snapshot usado
  en 1_v2; el resto de joins de este query siguen sobre
  `OriginacionPROD_SNAPSHOT`. También cambia el filtro
  `IdDesembolsodetalle IN (1,2,6,7)` → `IN (1,6,7)`, se agrega una rama nueva
  en CANAL GIRO (`bMantenimientoPrepagado=1 AND IdDesembolsoDetalle=6` →
  `'GIRO ACH'`), y cambia `=` por `>` en el filtro final de CORTE DISPERSION.
  **Pendiente:** confirmar con el DBA el nombre real del DB LINK
  `dbl_originacionprod` (servidor productivo, distinto del de snapshot).
- `TOTAL_DETALLE_DESEMBOLSO_ORACLE_2V2.sql` — el join hacia Seguros pasa de
  LEFT JOIN a INNER JOIN, el filtro de fecha ya no resta 17 días
  (`getdate()` en vez de `getdate()-17`), y cambia `=` por `>` en el filtro
  final.
- `TOTAL_DETALLE_GIRO_ORACLE_2V2.sql` — único cambio: `=` por `>` en el
  filtro final de CORTE DISPERSION.

Los comentarios inertes presentes en el SQL Server original de 2_v2
(`--and a.OP <> 1219460`, `--and a.Solicitud <> 1219460`,
`--and dre.Solicitud <> 1219460`, rama comentada de `bBlindaje`) se
preservaron como comentarios en Oracle; no son filtros activos y no afectan
el resultado.

`HELPER_FUNCTIONS_ORACLE.sql` (sección 6) es compartido por ambas versiones
(1_v2 y 2_v2): solo es necesario ejecutarlo una vez en el esquema
`bdpremierprueba`.


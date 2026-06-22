/* ============================================================================
   FECHA_FIN_MES_ORACLE.sql
   Version de origen: 2_v2 (idéntica a 1_v2 para este query; confirmado en
   OrdendeGiroReporteDispersionesMensuales.md: "Los dos query son identicos").
   Conversion de SQL Server -> Oracle, compatible con GoAnywhere MFT (JDBC).
   Misma logica que FECHA_INICIO_MES_ORACLE.sql pero retrocediendo dias en
   vez de avanzar, para encontrar el ULTIMO dia habil del mes anterior.

   NOTA: se preserva la misma inconsistencia del original (las dos primeras
   ramas consultan festivos con SYSDATE-N en vez de @DiaFinMes-N). No se
   corrige la logica, solo se traduce la sintaxis.
   ============================================================================ */

WITH base AS (
    SELECT
        TRUNC(SYSDATE) AS hoy,
        LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE), -1)) AS dia_fin_mes   -- ultimo dia del mes anterior
    FROM dual
),
dow_calc AS (
    SELECT
        hoy,
        dia_fin_mes,
        MOD(dia_fin_mes - TRUNC(dia_fin_mes,'IW') + 1, 7) + 1 AS dow_fin
    FROM base
),
holiday_calc AS (
    SELECT
        d.*,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.hoy - 1), DATE '1900-01-01') AS fest_hoy_m1,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.hoy - 2), DATE '1900-01-01') AS fest_hoy_m2,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.dia_fin_mes), DATE '1900-01-01') AS fest_dia_fin
    FROM dow_calc d
)
SELECT
    TO_CHAR(
        CASE
            WHEN dow_fin = 7 AND dia_fin_mes - 1 <> fest_hoy_m1 THEN dia_fin_mes - 1
            WHEN dow_fin = 1 AND dia_fin_mes - 2 <> fest_hoy_m2 THEN dia_fin_mes - 2
            WHEN dow_fin = 7 AND dia_fin_mes - 1 =  fest_hoy_m1 THEN dia_fin_mes - 2
            WHEN dow_fin = 1 AND dia_fin_mes - 2 =  fest_hoy_m2 THEN dia_fin_mes - 3
            WHEN dow_fin = 2 AND dia_fin_mes = fest_dia_fin THEN dia_fin_mes - 3
            WHEN dow_fin IN (3,4,5,6) AND dia_fin_mes = fest_dia_fin THEN dia_fin_mes - 1
            ELSE dia_fin_mes
        END,
    'YYMMDD') AS ultimo_dia_mes
FROM holiday_calc;

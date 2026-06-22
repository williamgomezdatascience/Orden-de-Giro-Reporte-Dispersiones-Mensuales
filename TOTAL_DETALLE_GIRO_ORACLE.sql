/* ============================================================================
   TOTAL_DETALLE_GIRO_ORACLE.sql
   Conversion de SQL Server -> Oracle, compatible con GoAnywhere MFT (JDBC).
   Version de origen: 1_v2 (confirmada por el usuario).

   Notas de esta consulta:
   - Solo 7 columnas en el SELECT original ('TOTAL' + 5 placeholders '' +
     VLRGIRAR). La columna [CORTE DISPERSION] esta comentada en el SELECT
     del SQL Server original (solo se usa, sin alias de salida, dentro del
     WHERE) por lo tanto NO se incluye como columna de salida aqui tampoco.
   - Filtro idDesembolsodetalle IN (1,2,6,7) (version 1_v2; en 2_v2 cambia a
     (1,6,7), ver NOTAS_MIGRACION.md).
   - Comparacion final con CORTE DISPERSION usa '=' (version 1_v2; en 2_v2
     cambia a '>').
   - OJO: igual que en TOTAL_DETALLE_DESEMBOLSO_ORACLE.sql, las columnas ''
     se evaluan como NULL en Oracle (no como cadena vacia); validar con
     GoAnywhere si esto afecta el archivo de salida.
   ============================================================================ */

WITH base_fechas AS (
    SELECT
        TRUNC(SYSDATE) AS hoy,
        TRUNC(LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE), -2))) + 1 AS dia_ini_mes,  -- primer dia mes anterior
        TRUNC(LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE), -1))) + 1 AS dia_fin_mes  -- primer dia mes actual
    FROM dual
),
dow_calc AS (
    SELECT
        hoy, dia_ini_mes, dia_fin_mes,
        MOD(dia_ini_mes - TRUNC(dia_ini_mes,'IW') + 1, 7) + 1 AS dow_ini,
        MOD(dia_fin_mes - TRUNC(dia_fin_mes,'IW') + 1, 7) + 1 AS dow_fin
    FROM base_fechas
),
holiday_calc AS (
    SELECT
        d.*,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.hoy + 2), DATE '1900-01-01') AS fest_hoy_p2,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.hoy + 1), DATE '1900-01-01') AS fest_hoy_p1,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.dia_ini_mes), DATE '1900-01-01') AS fest_dia_ini,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.dia_fin_mes), DATE '1900-01-01') AS fest_dia_fin
    FROM dow_calc d
),
fechas_habiles AS (
    SELECT
        hoy, dia_ini_mes, dia_fin_mes,
        CASE
            WHEN dow_ini = 7 AND dia_ini_mes + 2 <> fest_hoy_p2 THEN dia_ini_mes + 2
            WHEN dow_ini = 1 AND dia_ini_mes + 1 <> fest_hoy_p1 THEN dia_ini_mes + 1
            WHEN dow_ini = 7 AND dia_ini_mes + 2 =  fest_hoy_p2 THEN dia_ini_mes + 3
            WHEN dow_ini = 1 AND dia_ini_mes + 1 =  fest_hoy_p1 THEN dia_ini_mes + 2
            WHEN dow_ini IN (2,3,4,5) AND dia_ini_mes = fest_dia_ini THEN dia_ini_mes + 1
            WHEN dow_ini = 6 AND dia_ini_mes = fest_dia_ini THEN dia_ini_mes + 3
            ELSE dia_ini_mes
        END AS primer_dia_habil_mes,
        CASE
            WHEN dow_fin = 7 AND dia_fin_mes + 2 <> fest_hoy_p2 THEN dia_fin_mes + 2
            WHEN dow_fin = 1 AND dia_fin_mes + 1 <> fest_hoy_p1 THEN dia_fin_mes + 1
            WHEN dow_fin = 7 AND dia_fin_mes + 2 =  fest_hoy_p2 THEN dia_fin_mes + 3
            WHEN dow_fin = 1 AND dia_fin_mes + 1 =  fest_hoy_p1 THEN dia_fin_mes + 2
            WHEN dow_fin IN (2,3,4,5) AND dia_fin_mes = fest_dia_fin THEN dia_fin_mes + 1
            WHEN dow_fin = 6 AND dia_fin_mes = fest_dia_fin THEN dia_fin_mes + 3
            ELSE dia_fin_mes
        END AS primer_dia_mes
    FROM holiday_calc
)
SELECT
    'TOTAL',                                                                                      -- 1
    '',                                                                                            -- 2
    '',                                                                                            -- 3
    '',                                                                                            -- 4
    '',                                                                                            -- 5
    '',                                                                                            -- 6
    '$' || REPLACE(TO_CHAR(NVL(SUM(ABS(NVL(dre.montoDesembolsar,0))),0)),' ','') AS VLRGIRAR       -- 7
FROM bdpremieroriginacion.desembolso dsm
LEFT JOIN bdpremieroriginacion.desembolsorelacion dre ON dre.solicitud = dsm.Solicitud
CROSS JOIN fechas_habiles fh
WHERE dre.IdDesembolsodetalle IN (1,2,6,7)
  AND TO_CHAR(dre.fechaenvio,'YYYYMM') = TO_CHAR(
          CASE WHEN fh.hoy = fh.primer_dia_mes THEN ADD_MONTHS(fh.primer_dia_mes,-1) END,
      'YYYYMM')
  AND (CASE
         WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '07' AND '09' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.0900'
         WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '11' AND '13' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1300'
         WHEN TO_CHAR(dre.fechaenvio,'HH24') IN ('14','15') THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1500'
       END) = TO_CHAR(fh.primer_dia_habil_mes,'YYMMDD') || '.0900';

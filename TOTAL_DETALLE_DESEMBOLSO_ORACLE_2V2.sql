/* ============================================================================
   TOTAL_DETALLE_DESEMBOLSO_ORACLE_2V2.sql
   Conversion de SQL Server -> Oracle, compatible con GoAnywhere MFT (JDBC).
   Version de origen: 2_v2.

   Diferencias respecto a la version 1_v2 (ver TOTAL_DETALLE_DESEMBOLSO_ORACLE.sql):
   - El join hacia Seguros pasa de LEFT JOIN a INNER JOIN.
   - El filtro de fecha ya NO resta 17 dias (getdate() en vez de getdate()-17).
   - La comparacion final contra CORTE DISPERSION pasa de '=' a '>'.
   - Se agrega un comentario inerte "--and dre.Solicitud <> 1219460" en el
     original (no es un filtro activo, no se traduce a SQL ejecutable).

   El resto de la logica (31 columnas, sin GROUP BY, CTEs de fechas habiles,
   etc.) es igual a la version 1_v2. Ver notas generales y supuestos en
   NOTAS_MIGRACION.md.
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
    'Totales',                                                                                          -- 1
    '',                                                                                                  -- 2  (FECHA, no usado)
    '',                                                                                                  -- 3  (NUMEROCREDITO, no usado)
    '',                                                                                                  -- 4  (NOMBRE, no usado)
    '',                                                                                                  -- 5  (TIPO CC/CE, no usado)
    '',                                                                                                  -- 6  (CC/CE, no usado)
    '',                                                                                                  -- 7  (PLAZOMESES, no usado)
    '',                                                                                                  -- 8  (INTERES, no usado)
    '',                                                                                                  -- 9  (VLRVEHICULOFACTURA, no usado)
    '$' || REPLACE(TO_CHAR(NVL(SUM(NVL(ope.MontoaFinanciarSinSeguros,0)),0)),' ','') AS VLRFINANCIARVEHICULO,   -- 10
    '$' || REPLACE(TO_CHAR(NVL(SUM(NVL(est.ValorSubvecionado,0)),0)),' ','') AS VLRSUBVENCION,                  -- 11
    REPLACE(bdpremierprueba.formatmoney(NVL(SUM(NVL(seg.iValorMantenimiento,0)),0),30,'','',',',''),' ','') AS MANTENIMIENTO_PREPAGADO, -- 12
    '$' || REPLACE(TO_CHAR(NVL(SUM(NVL(fac.ValorAccesoriosFactura,0)),0)),' ','') AS VLRACCESORIOS,             -- 13
    '',                                                                                                  -- 14 (VLRVIDA, no usado)
    '',                                                                                                  -- 15 (VLRPROTECCIONFINANCIERA, no usado)
    '',                                                                                                  -- 16 (VLRSEGUROVEHICULO, no usado)
    '$' || REPLACE(bdpremierprueba.formatmoney(NVL(SUM(NVL(seg.BonoAstara,0)),0),30,'','',',',''),' ','') AS BONO_POLIZA,  -- 17
    '',                                                                                                  -- 18 (GMF, no usado)
    '',                                                                                                  -- 19 (RGM, no usado)
    '$' || REPLACE(TO_CHAR(SUM(dsm.montoDesembolsar)),' ','') AS TOTALDESEMBOLSO,                        -- 20
    '',                                                                                                  -- 21 (duplicado comentado, no usado)
    '',                                                                                                  -- 22 (FECHAPAGO, no usado)
    '',                                                                                                  -- 23 (MARCA, no usado)
    '',                                                                                                  -- 24 (LINEA, no usado)
    '',                                                                                                  -- 25 (MODELO, no usado)
    '',                                                                                                  -- 26 (FASECOLDA, no usado)
    '',                                                                                                  -- 27 (PLACA, no usado)
    '',                                                                                                  -- 28 (CHASIS, no usado)
    '',                                                                                                  -- 29 (MOTOR, no usado)
    '',                                                                                                  -- 30 (MODALIDADPAGOSEGUROVIDA, no usado)
    ''                                                                                                   -- 31 (MODALIDADPROTECCIONFINANCIERA, no usado)
FROM bdpremieroriginacion.desembolso dsm
LEFT JOIN bdpremieroriginacion.desembolsorelacion dre ON dre.solicitud = dsm.Solicitud
-- left join reportes.originacion_solicitudes sor on dsm.Solicitud = sor.solicitud  -- comentado en el original
INNER JOIN originacionprod_snapshot.originacion@dbl_originacionprod_snapshot ori ON ori.caso = dsm.Solicitud
INNER JOIN originacionprod_snapshot.datosfactura@dbl_originacionprod_snapshot fac ON ori.DatosFactura = fac.idDatosFactura
INNER JOIN originacionprod_snapshot.informacionestudio@dbl_originacionprod_snapshot est ON ori.InformaciondeEstudio = est.idInformacionestudio
INNER JOIN originacionprod_snapshot.operaciones@dbl_originacionprod_snapshot ope ON ori.Operaciones = ope.idOPeraciones
INNER JOIN originacionprod_snapshot.seguros@dbl_originacionprod_snapshot seg ON ori.Seguros = seg.idSeguros          -- 2_v2: INNER JOIN (en 1_v2 era LEFT JOIN)
CROSS JOIN fechas_habiles fh
WHERE TO_CHAR(dre.fechaenvio,'YYYYMM') = TO_CHAR(
          CASE WHEN fh.hoy = fh.primer_dia_mes THEN ADD_MONTHS(fh.primer_dia_mes,-1) END,                -- 2_v2: sin "-17" (en 1_v2 era fh.hoy - 17)
      'YYYYMM')
  AND dre.idDesembolsoDetalle = 1
  AND (CASE
         WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '07' AND '09' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.0900'
         WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '11' AND '13' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1300'
         WHEN TO_CHAR(dre.fechaenvio,'HH24') IN ('14','15') THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1500'
       END) > TO_CHAR(fh.primer_dia_habil_mes,'YYMMDD') || '.0900';                                      -- 2_v2: '>' (en 1_v2 era '=')
-- AND dre.Solicitud <> 1219460   -- comentado en el original, sin efecto

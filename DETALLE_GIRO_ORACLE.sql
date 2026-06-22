/* ============================================================================
   DETALLE_GIRO_ORACLE.sql
   Conversion de SQL Server -> Oracle, compatible con GoAnywhere MFT (JDBC).
   Version de origen: 1_v2 (confirmada por el usuario).

   Cambios principales de sintaxis (ver detalle completo en
   DETALLE_DESEMBOLSO_ORACLE.sql y NOTAS_MIGRACION.md):
   - DECLARE/SET -> CTEs (WITH base_fechas/dow_calc/holiday_calc/fechas_habiles)
   - getdate() -> SYSDATE / TRUNC(SYSDATE)
   - isnull(x,y) -> NVL(x,y)
   - '+' (concatenacion) -> '||'
   - [identificador con espacio] -> "identificador con espacio"
   - servidores enlazados [180.26.149.41].[OriginacionPROD_SNAPSHOT].[dbo].tabla
     -> originacionprod_snapshot.tabla@dbl_originacionprod_snapshot
   - bdpremierprueba.dbo.FormatMoney -> bdpremierprueba.formatmoney (ver
     HELPER_FUNCTIONS_ORACLE.sql)
   - BDPremierPrueba.dbo.Format_DateToString('AAMMDD',fecha) -> TO_CHAR(fecha,'YYMMDD')

   Supuestos especificos de este query (pendientes de validar):
   - "numeroCuenta" y "tipoCuenta" (sin alias en el SELECT original) se asumen
     columnas de BDPremierOriginacion.dbo.DesembolsoRelacion (alias dre), ya
     que es la unica tabla de la consulta relacionada con datos bancarios del
     giro.
   - "ope.OperacionCancelarPM/PM2/PM3" y "valorcruce1/2/3" (sin alias) se
     asumen columnas de OriginacionPROD_SNAPSHOT.dbo.Operaciones (alias ope),
     ya que ope.OperacionCancelarPM se referencia explicitamente asi en el
     query original. Se preserva la falta de alias de valorcruce1/2/3 y de
     las condiciones WHEN tal cual estaba en el SQL Server original (no se
     agregan calificadores que no existian).
   - "solicitud" (sin alias) en el join hacia Originacion se asume
     dre.Solicitud.
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
        MOD(hoy         - TRUNC(hoy,'IW')         + 1, 7) + 1 AS dow_hoy,
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
        hoy, dow_hoy, dia_ini_mes, dia_fin_mes,
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
SELECT *
FROM (
    SELECT DISTINCT
        dre.Solicitud AS SOLICITUD,
        dre.razonSocial AS BENEFICIARIO,
        dre.numeroIdentificacion AS "CC/NIT/CE",
        ban.Nombre AS BANCO,
        CASE
            WHEN ope.planmayor = 1 AND dre.IdDesembolsoDetalle = 1 AND pm1.idInformacionPM IS NULL THEN
                CASE
                    WHEN OperacionaCancelarPM2 IS NOT NULL AND OperacionaCancelarPM3 IS NOT NULL THEN
                        ope.OperacionCancelarPM || ' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(valorcruce1),30,'','',',',''),' ','')
                        || ' // ' || ope.OperacionaCancelarPM2 || ' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(valorcruce2),30,'','',',',''),' ','')
                        || ' // ' || ope.OperacionaCancelarPM3 || ' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(valorcruce3),30,'','',',',''),' ','')
                    WHEN OperacionaCancelarPM2 IS NOT NULL THEN
                        ope.OperacionCancelarPM || ' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(valorcruce1),30,'','',',',''),' ','')
                        || ' // ' || ope.OperacionaCancelarPM2 || ' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(valorcruce2),30,'','',',',''),' ','')
                    ELSE
                        ope.OperacionCancelarPM || ' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(valorcruce1),30,'','',',',''),' ','')
                END
            WHEN ope.planmayor = 1 AND pm1.idInformacionPM IS NOT NULL THEN
                PM1.Operacionacancelar ||
                CASE
                    WHEN PM2.Operacionacancelar IS NULL THEN
                        REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm1.valorcruce,0)),30,'','',',',''),' ','') || ' // ', '//', '')
                    ELSE
                        ' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(pm1.valorcruce),30,'','',',',''),' ','') || ' // '
                END ||
                NVL(PM2.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm2.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM3.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM3.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm3.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM4.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM4.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm4.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM5.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM5.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm5.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM6.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM6.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm6.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM7.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM7.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm7.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM8.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM8.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm8.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM9.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM9.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm9.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
                    || CASE WHEN PM10.Operacionacancelar IS NOT NULL THEN '//' ELSE '' END ||
                NVL(PM10.Operacionacancelar,'') || REPLACE(' - $' || REPLACE(bdpremierprueba.formatmoney(ABS(NVL(pm10.valorcruce,0)),30,'','',',',''),' ',''), ' - $0,00','')
            ELSE numeroCuenta
        END AS NUMEROCUENTA,
        CASE WHEN ope.planmayor = 1 THEN '' ELSE tipoCuenta END AS TIPOCUENTA,
        '$' || REPLACE(bdpremierprueba.formatmoney(
                  CASE WHEN seg.bMantenimientoPrepagado = 1 AND dre.IdDesembolsoDetalle = 6 THEN ABS(dre.montoDesembolsar)
                       ELSE ABS(dre.montoDesembolsar + NVL(df.ValorAccesoriosFactura,0))
                  END, 30,'','',',',''),' ','') AS VLRGIRAR,
        CASE
            WHEN ope.planmayor = 1 AND PM1.Operacionacancelar LIKE '81%' THEN 'PAGO ALTAIR'
            WHEN ope.planmayor = 1 AND PM1.Operacionacancelar LIKE '98%' THEN 'PAGO BOT'
            WHEN ope.planmayor = 1 AND PM1.Operacionacancelar LIKE '75%' THEN 'PAGO ALTAIR'
            ELSE 'GIRO ACH'
        END AS "CANAL GIRO",
        UPPER(
            CASE
                WHEN seg.bMantenimientoPrepagado = 1 AND dre.IdDesembolsoDetalle = 6 THEN 'Mantenimiento Prepagado'
                WHEN NVL(est.ValorSubvecionado,0) > 0 AND NVL(seg.BonoAstara,0) > 0 AND NVL(df.ValorAccesoriosFactura,0) > 0
                     THEN 'Con Accesorios ' || 'Subvencionado' || '-' || 'Descuento Bono poliza $' || CAST(ABS(NVL(CAST(seg.BonoAstara AS NUMBER),0)) AS VARCHAR2(50))
                WHEN NVL(est.ValorSubvecionado,0) > 0 AND NVL(seg.BonoAstara,0) > 0
                     THEN 'Subvencionado' || '-' || 'Descuento Bono poliza $' || CAST(ABS(NVL(CAST(seg.BonoAstara AS NUMBER),0)) AS VARCHAR2(50))
                WHEN NVL(est.ValorSubvecionado,0) > 0 THEN 'Subvencionado'
                WHEN NVL(seg.BonoAstara,0) > 0 THEN 'Descuento Bono poliza $' || CAST(ABS(NVL(CAST(seg.BonoAstara AS NUMBER),0)) AS VARCHAR2(50))
                WHEN NVL(df.ValorAccesoriosFactura,0) > 0 THEN 'Accesorios'
                ELSE ''
            END
        ) AS OBSERVACIONES,
        CASE
            WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '07' AND '09' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.0900'
            WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '11' AND '13' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1300'
            WHEN TO_CHAR(dre.fechaenvio,'HH24') IN ('14','15') THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1500'
        END AS "CORTE DISPERSION"
    FROM bdpremieroriginacion.desembolsorelacion dre
    INNER JOIN bdpremierprueba.banco ban ON ban.Id = dre.idBanco
    LEFT JOIN originacionprod_snapshot.originacion@dbl_originacionprod_snapshot ori ON ori.caso = dre.solicitud
    LEFT JOIN originacionprod_snapshot.operaciones@dbl_originacionprod_snapshot ope ON ope.IdOperaciones = ori.operaciones
    LEFT JOIN originacionprod_snapshot.datosfactura@dbl_originacionprod_snapshot df ON df.idDatosFactura = ori.DatosFactura
    LEFT JOIN originacionprod_snapshot.informacionestudio@dbl_originacionprod_snapshot est ON ori.InformaciondeEstudio = est.idInformacionestudio
    LEFT JOIN originacionprod_snapshot.seguros@dbl_originacionprod_snapshot seg ON ori.Seguros = seg.idSeguros
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM1
           ON PM1.DatosFactura = df.idDatosFactura AND PM1.conteo = 1
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM2
           ON PM2.DatosFactura = df.idDatosFactura AND PM2.conteo = 2
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM3
           ON PM3.DatosFactura = df.idDatosFactura AND PM3.conteo = 3
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM4
           ON PM4.DatosFactura = df.idDatosFactura AND PM4.conteo = 4
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM5
           ON PM5.DatosFactura = df.idDatosFactura AND PM5.conteo = 5
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM6
           ON PM6.DatosFactura = df.idDatosFactura AND PM6.conteo = 6
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM7
           ON PM7.DatosFactura = df.idDatosFactura AND PM7.conteo = 7
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM8
           ON PM8.DatosFactura = df.idDatosFactura AND PM8.conteo = 8
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM9
           ON PM9.DatosFactura = df.idDatosFactura AND PM9.conteo = 9
    LEFT JOIN (SELECT ROW_NUMBER() OVER (PARTITION BY DatosFactura ORDER BY idinformacionPM ASC) AS conteo, t.*
                 FROM originacionprod_snapshot.informacionpm@dbl_originacionprod_snapshot t) PM10
           ON PM10.DatosFactura = df.idDatosFactura AND PM10.conteo = 10
    CROSS JOIN fechas_habiles fh
    WHERE TO_CHAR(dre.fechaenvio,'YYYYMM') = TO_CHAR(
              CASE WHEN fh.hoy = fh.primer_dia_mes THEN ADD_MONTHS(fh.primer_dia_mes,-1) END,
          'YYYYMM')
      AND fh.dow_hoy NOT IN (1,7)
      AND dre.IdDesembolsodetalle IN (1,2,6,7)
) a
WHERE a."CORTE DISPERSION" = (SELECT TO_CHAR(primer_dia_habil_mes,'YYMMDD') || '.0900' FROM fechas_habiles)
ORDER BY 10 ASC;

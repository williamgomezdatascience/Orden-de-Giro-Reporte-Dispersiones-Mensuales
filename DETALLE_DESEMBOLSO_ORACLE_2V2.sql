/* ============================================================================
   DETALLE_DESEMBOLSO_ORACLE_2V2.sql
   Conversion de SQL Server -> Oracle, compatible con GoAnywhere MFT (JDBC).
   Version de origen: 2_v2.

   Diferencias respecto a la version 1_v2 (ver DETALLE_DESEMBOLSO_ORACLE.sql):
   - La comparacion final contra CORTE DISPERSION pasa de '=' a '>'.
   - El ORDER BY pasa de la columna 29 a la columna 32 (ahora SI apunta a la
     ultima columna real del SELECT, CORTE DISPERSION).
   - Se agrega un comentario inerte "--and a.OP <> 1219460" en el original
     (no es un filtro activo).
   - Se agrega un comentario inerte para una columna VLRBLINDAJE (no se
     selecciona realmente, queda comentada en el original).
   El resto del query (32 columnas, joins, CTEs de fechas habiles) es igual
   a la version 1_v2.

   Cambios principales de sintaxis:
   - DECLARE/SET                -> CTEs (WITH) "base/dow_calc/holiday_calc/
                                   fechas_habiles" que calculan las mismas
                                   fechas de negocio (primer dia habil del
                                   mes anterior y del mes actual).
   - getdate()                  -> SYSDATE / TRUNC(SYSDATE)
   - eomonth(d,n)                -> LAST_DAY(ADD_MONTHS(d,n))
   - dateadd(day/month,n,d)      -> d + n  /  ADD_MONTHS(d,n)
   - datepart(dw,d)              -> formula con TRUNC(d,'IW') (independiente
                                    de NLS_TERRITORY de la sesion)
   - isnull(x,y)                 -> NVL(x,y)
   - convert(varchar,d,103)      -> TO_CHAR(d,'DD/MM/YYYY')
   - format(d,'yyyyMM'/'HH'/...) -> TO_CHAR(d,'YYYYMM'/'HH24'/'YYMMDD')
   - concatenacion '+'           -> '||'
   - [identificador con espacio] -> "identificador con espacio"
   - alias 'TEXTO' (comillas simples) -> alias "TEXTO" (comillas dobles)
   - servidores enlazados [ip].[base].[dbo].[tabla] -> esquema.tabla@DB_LINK
     (ver notas de supuestos en NOTAS_MIGRACION.md)
   - bdpremierprueba.dbo.Format_Number / FormatMoney -> mismas funciones,
     recreadas en Oracle (ver HELPER_FUNCTIONS_ORACLE.sql). Se asume que se
     despliegan en el esquema BDPREMIERPRUEBA.
   - BDPremierPrueba.dbo.Format_DateToString('AAMMDD', fecha) -> se reemplazo
     en linea por TO_CHAR(fecha,'YYMMDD') porque en estos reportes solo se
     usa con esa mascara fija.

   NOTA: se preserva la inconsistencia original donde el chequeo de festivos
   de las 2 primeras ramas de cada CASE de "dia habil" usa SYSDATE+/-N en vez
   de la fecha ancla del mes +/-N. No se corrige la logica de negocio, solo
   se traduce la sintaxis tal cual estaba en el SQL Server original.

   Pendiente de validar con el equipo DBA / migracion Bantotal:
   - Nombres reales de los DB LINK de Oracle (dbl_originacionprod_snapshot,
     dbl_originacionprod).
   - Si BDPremierOriginacion, BDPremierPrueba, BDFinanciera y reportes pasan
     a ser esquemas dentro de la misma instancia Oracle o requieren su propio
     DB LINK.
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
        dsm.Solicitud AS OP,
        TO_CHAR(dre.FechaEnvio,'DD/MM/YYYY') AS FECHA,
        dsm.numeroCredito AS NUMEROCREDITO,
        CASE
            WHEN sor.Nombres IS NULL THEN
                CASE
                    WHEN cli.NombreConcatenado IS NOT NULL THEN REPLACE(CAST(cli.NombreConcatenado AS VARCHAR2(100)), 'Cliente : ', '')
                    ELSE UPPER(cli.Apellido1 || ' ' || NVL(cli.Apellido2,'') || ', ' || cli.Nombre1 || ' ' || NVL(cli.Nombre2,''))
                END
            ELSE sor.Nombres
        END AS NOMBRE,
        dsm.tipoIdentificacion AS "TIPO CC/CE",
        dsm.numeroIdentificacion AS "CC/CE",
        (CASE pla.unidadTiempo WHEN 'M' THEN '2' WHEN 'A' THEN '3' ELSE '0' END)
            || bdpremierprueba.format_number(pla.Cuotas,'',3,0) AS PLAZOMESES,
        tas.Efectiva AS INTERES,
        '$' || REPLACE(TO_CHAR(fac.ValorVehiculoFactura), ' ', '') AS VLRVEHICULOFACTURA,
        '$' || REPLACE(TO_CHAR(ope.MontoaFinanciarSinSeguros), ' ', '') AS VLRFINANCIARVEHICULO,
        '$' || REPLACE(TO_CHAR(NVL(est.ValorSubvecionado,0)), ' ', '') AS VLRSUBVENCION,
        '$' || REPLACE(bdpremierprueba.formatmoney(NVL(seg.iValorMantenimiento,0),30,'','',',',''), ' ', '') AS MANTENIMIENTO_PREPAGADO,
        -- (en el original hay una linea comentada para VLRBLINDAJE via seg.iValorBlindaje; no se selecciona, sin efecto)
        '$' || REPLACE(TO_CHAR(NVL(fac.ValorAccesoriosFactura,0)), ' ', '') AS VLRACCESORIOS,
        '$' || REPLACE(TO_CHAR(NVL(seg.PrimaSegurodeVida,0)), ' ', '') AS VLRVIDA,
        '$' || REPLACE(TO_CHAR(NVL(seg.PrimaSegurodeDesempleo, NVL(seg.ValorProteccionFinancieraM, 0))), ' ', '') AS VLRPROTECCIONFINANCIERA,
        '$' || REPLACE(TO_CHAR(NVL(seg.PrimaSegurodeAutomovil,0)), ' ', '') AS VLRSEGUROVEHICULO,
        NVL(seg.BonoAstara,0) AS "BONO POLIZA",
        NVL(seg.valorPolizaTR,0) AS "VLR TR A FINANCIAR",
        '$' || REPLACE(TO_CHAR(NVL(ope.GMF,0)), ' ', '') AS GMF,
        '$' || REPLACE(TO_CHAR(CASE WHEN est.tipodeGarantia = 2 THEN 0 ELSE NVL(rgm.RGM,0) END), ' ', '') AS RGM,
        '$' || REPLACE(TO_CHAR(dsm.montoDesembolsar), ' ', '') AS TOTALDESEMBOLSO,
        dpa.DiadePagoCuota AS FECHAPAGO,
        NVL(fac.MarcaFactura, sor.Marca) AS MARCA,
        NVL(fac.LineaFactura, sor.LineaVeh) AS LINEA,
        NVL(fac.ModeloFactura, sor.Modelo) AS MODELO,
        CASE WHEN sor.fasecolda IS NULL THEN fas.fasecolda ELSE sor.fasecolda END AS FASECOLDA,
        fac.Placa AS PLACA,
        fac.ChasisFactura AS CHASIS,
        fac.MotorFactura AS MOTOR,
        mds.Valor AS MODALIDADPAGOSEGUROVIDA,
        CASE
            WHEN seg.PrimaSegurodeDesempleo > 0 THEN 'Anual'
            WHEN seg.ValorProteccionFinancieraM > 0 THEN 'Mensual'
            ELSE ''
        END AS MODALIDADPROTECCIONFINANCIERA,
        CASE
            WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '07' AND '09' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.0900'
            WHEN TO_CHAR(dre.fechaenvio,'HH24') BETWEEN '11' AND '13' THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1300'
            WHEN TO_CHAR(dre.fechaenvio,'HH24') IN ('14','15') THEN TO_CHAR(dre.fechaenvio,'YYMMDD') || '.1500'
        END AS "CORTE DISPERSION"
    FROM bdpremieroriginacion.desembolso dsm
    LEFT JOIN bdpremieroriginacion.desembolsorelacion dre ON dre.solicitud = dsm.Solicitud
    LEFT JOIN reportes.originacion_solicitudes sor ON dsm.Solicitud = sor.solicitud
    INNER JOIN originacionprod_snapshot.originacion@dbl_originacionprod_snapshot ori ON ori.caso = dsm.Solicitud
    INNER JOIN originacionprod_snapshot.datosfactura@dbl_originacionprod_snapshot fac ON ori.DatosFactura = fac.idDatosFactura
    INNER JOIN originacionprod_snapshot.seguros@dbl_originacionprod_snapshot seg ON ori.Seguros = seg.idSeguros
    INNER JOIN originacionprod_snapshot.informacionestudio@dbl_originacionprod_snapshot est ON ori.InformaciondeEstudio = est.idInformacionestudio
    INNER JOIN originacionprod_snapshot.operaciones@dbl_originacionprod_snapshot ope ON ori.Operaciones = ope.idOPeraciones
    INNER JOIN originacionprod_snapshot.planfinanciacion@dbl_originacionprod_snapshot pla ON ori.PlanFinanciacion = pla.idPlanFinanciacion
    INNER JOIN originacionprod_snapshot.tasas_ek@dbl_originacionprod_snapshot tas1 ON est.Tasa = tas1.idTasas
    INNER JOIN originacionprod_snapshot.tasas@dbl_originacionprod_snapshot tas ON tas1.id1 = tas.id1
    LEFT JOIN originacionprod_snapshot.diadepago@dbl_originacionprod_snapshot dpa ON ope.DiadePago = dpa.idDiadePago
    LEFT JOIN originacionprod_snapshot.modalidadpagosegurovida@dbl_originacionprod_snapshot mds ON mds.idModalidadPagoSegurovida = seg.ModalidadPagoseguroVida
    LEFT JOIN originacionprod_snapshot.cliente@dbl_originacionprod_snapshot cli ON ori.Cliente = cli.idCliente
    LEFT JOIN originacionprod_snapshot.vehiculo@dbl_originacionprod_snapshot veh ON ori.Vehiculo = veh.idVehiculo
    LEFT JOIN originacionprod_snapshot.fasecolda_ref3_ek@dbl_originacionprod_snapshot re3 ON veh.FASECOLDA = re3.idFASECOLDA_REF3
    LEFT JOIN originacionprod_snapshot.fasecolda_ref3@dbl_originacionprod_snapshot fas ON re3.id1 = fas.id1
    LEFT JOIN originacionprod_snapshot.registrogarantiamobiliar@dbl_originacionprod_snapshot rgm ON rgm.idRegistroGarantiaMobiliar = ope.rgm
    CROSS JOIN fechas_habiles fh
    WHERE TO_CHAR(dre.fechaenvio,'YYYYMM') = TO_CHAR(
              CASE WHEN fh.hoy = fh.primer_dia_mes THEN ADD_MONTHS(fh.primer_dia_mes,-1) END,
          'YYYYMM')
      AND fh.dow_hoy NOT IN (1,7)
      AND dsm.IdDesembolsodetalle = 1
) a
WHERE a."CORTE DISPERSION" > (SELECT TO_CHAR(primer_dia_habil_mes,'YYMMDD') || '.0900' FROM fechas_habiles)
-- AND a.OP <> 1219460   -- comentado en el original, sin efecto
ORDER BY 32 ASC;

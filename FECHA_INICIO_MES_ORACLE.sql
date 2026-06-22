/* ============================================================================
   FECHA_INICIO_MES_ORACLE.sql
   Conversion de SQL Server -> Oracle, compatible con GoAnywhere MFT (JDBC).
   - Se elimino el bloque DECLARE/SET (Oracle SQL puro no admite variables de
     sesion fuera de PL/SQL). Se reemplazo por CTEs (WITH) que calculan los
     mismos valores. Esto permite que GoAnywhere ejecute el script como un
     unico SELECT y obtenga un ResultSet, igual que con un SELECT directo.
   - getdate()      -> SYSDATE
   - eomonth(d,n)    -> LAST_DAY(ADD_MONTHS(d,n))
   - dateadd(day,n,d)-> d + n
   - datepart(dw,d)  -> formula NLS-independiente basada en TRUNC(d,'IW')
                        (ver nota mas abajo). Replica el esquema de
                        SQL Server con @@DATEFIRST = 7 (1=Domingo...7=Sabado).
   - isnull(x,y)     -> NVL(x,y)
   - format(d,'yyMMdd') -> TO_CHAR(d,'YYMMDD')

   NOTA IMPORTANTE (se preserva el comportamiento original, no se corrige):
   En las dos primeras ramas del CASE, el SQL Server original consulta la
   tabla de festivos usando getdate()+N (la fecha de HOY) en lugar de
   @DiaIniMes+N (la fecha ancla del mes). Esa inconsistencia se reproduce
   aqui tal cual viene en el query original. Validar con el negocio si esto
   es intencional antes de pasar a produccion.
   ============================================================================ */

WITH base AS (
    SELECT
        TRUNC(SYSDATE) AS hoy,
        TRUNC(LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE), -2))) + 1 AS dia_ini_mes   -- primer dia del mes anterior
    FROM dual
),
dow_calc AS (
    SELECT
        hoy,
        dia_ini_mes,
        -- Dia de la semana estilo SQL Server (1=Domingo ... 7=Sabado),
        -- calculado de forma independiente del NLS_TERRITORY de la sesion.
        MOD(dia_ini_mes - TRUNC(dia_ini_mes,'IW') + 1, 7) + 1 AS dow_ini
    FROM base
),
holiday_calc AS (
    SELECT
        d.*,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.hoy + 2), DATE '1900-01-01') AS fest_hoy_p2,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.hoy + 1), DATE '1900-01-01') AS fest_hoy_p1,
        NVL((SELECT fecha FROM bdfinanciera.diasfestivos WHERE fecha = d.dia_ini_mes), DATE '1900-01-01') AS fest_dia_ini
    FROM dow_calc d
)
SELECT
    TO_CHAR(
        CASE
            WHEN dow_ini = 7 AND dia_ini_mes + 2 <> fest_hoy_p2  THEN dia_ini_mes + 2
            WHEN dow_ini = 1 AND dia_ini_mes + 1 <> fest_hoy_p1  THEN dia_ini_mes + 1
            WHEN dow_ini = 7 AND dia_ini_mes + 2 =  fest_hoy_p2  THEN dia_ini_mes + 3
            WHEN dow_ini = 1 AND dia_ini_mes + 1 =  fest_hoy_p1  THEN dia_ini_mes + 2
            WHEN dow_ini IN (2,3,4,5) AND dia_ini_mes = fest_dia_ini THEN dia_ini_mes + 1
            WHEN dow_ini = 6 AND dia_ini_mes = fest_dia_ini THEN dia_ini_mes + 3
            ELSE dia_ini_mes
        END,
    'YYMMDD') AS primer_dia_habil_mes
FROM holiday_calc;

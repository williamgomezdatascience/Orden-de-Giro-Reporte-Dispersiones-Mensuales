/* ============================================================================
   HELPER_FUNCTIONS_ORACLE.sql
   Recreacion en Oracle PL/SQL de las funciones de usuario de SQL Server
   usadas por los reportes de dispersiones (bdpremierprueba.dbo.FormatMoney
   y bdpremierprueba.dbo.Format_Number).

   IMPORTANTE: Estas funciones se infirieron UNICAMENTE a partir de como se
   usan en los 6 queries (no se tuvo acceso al codigo fuente original de las
   funciones en SQL Server). Antes de pasar a produccion se debe:
     1) Comparar la salida de estas funciones Oracle contra la salida real
        de las funciones SQL Server originales para los mismos valores de
        entrada (incluyendo casos borde: NULL, 0, numeros negativos, valores
        muy grandes).
     2) Confirmar el esquema/usuario Oracle donde deben crearse (aqui se usa
        BDPREMIERPRUEBA como esquema, igual que en SQL Server).
     3) Otorgar GRANT EXECUTE a los usuarios/roles que ejecutan los reportes
        desde GoAnywhere MFT.

   En todos los 6 queries originales, FormatMoney SIEMPRE se invoca como:
       FormatMoney(<valor>, 30, '', '', ',', '')
   Es decir: longitud=30, prefijo='', sufijo='', separador_decimal=',',
   separador_miles='' (sin agrupacion). Esto se deduce porque varias formulas
   comparan el resultado contra el literal ' - $0,00' (coma como separador
   decimal, no de miles).
   ============================================================================ */

CREATE OR REPLACE FUNCTION bdpremierprueba.formatmoney (
    p_valor       IN NUMBER,
    p_longitud    IN NUMBER   DEFAULT 30,
    p_prefijo     IN VARCHAR2 DEFAULT NULL,
    p_sufijo      IN VARCHAR2 DEFAULT NULL,
    p_sep_decimal IN VARCHAR2 DEFAULT ',',
    p_sep_miles   IN VARCHAR2 DEFAULT NULL
) RETURN VARCHAR2
IS
    v_decimal   VARCHAR2(1);
    v_grupo     VARCHAR2(1);
    v_numero    VARCHAR2(100);
    v_resultado VARCHAR2(200);
BEGIN
    v_decimal := NVL(p_sep_decimal, ',');

    IF p_sep_miles IS NULL OR p_sep_miles = '' THEN
        -- Sin separador de miles: se usa un caracter neutro temporal (Oracle
        -- exige dos caracteres distintos en NLS_NUMERIC_CHARACTERS) y luego
        -- se elimina del resultado.
        v_grupo  := CASE WHEN v_decimal = '~' THEN '^' ELSE '~' END;
        v_numero := TO_CHAR(NVL(p_valor,0), 'FM999G999G999G999G990D00',
                       'NLS_NUMERIC_CHARACTERS = ''' || v_decimal || v_grupo || '''');
        v_numero := REPLACE(v_numero, v_grupo, '');
    ELSE
        v_grupo  := p_sep_miles;
        v_numero := TO_CHAR(NVL(p_valor,0), 'FM999G999G999G999G990D00',
                       'NLS_NUMERIC_CHARACTERS = ''' || v_decimal || v_grupo || '''');
    END IF;

    v_resultado := NVL(p_prefijo,'') || v_numero || NVL(p_sufijo,'');

    -- El original deja el resultado con relleno de espacios a la izquierda
    -- hasta p_longitud caracteres (de ahi que las consultas siempre hagan
    -- replace(...,' ','') para "limpiar" el numero).
    RETURN LPAD(v_resultado, p_longitud);
END formatmoney;
/

CREATE OR REPLACE FUNCTION bdpremierprueba.format_number (
    p_valor     IN NUMBER,
    p_mascara   IN VARCHAR2 DEFAULT NULL,
    p_longitud  IN NUMBER   DEFAULT 10,
    p_decimales IN NUMBER   DEFAULT 0
) RETURN VARCHAR2
IS
    v_resultado VARCHAR2(100);
BEGIN
    /* Implementacion best-effort: el unico uso real observado en estos
       reportes es Format_Number(pla.Cuotas,'',3,0), es decir, un entero
       (numero de cuotas) relleno con ceros a la izquierda hasta 3
       posiciones, sin mascara ni decimales. El comportamiento de p_mascara
       y de p_decimales > 0 NO esta validado contra la funcion original y
       se deja como aproximacion razonable. */
    IF NVL(p_decimales,0) <= 0 THEN
        v_resultado := LPAD(TO_CHAR(TRUNC(NVL(p_valor,0))), p_longitud, '0');
    ELSE
        v_resultado := LPAD(
            TO_CHAR(NVL(p_valor,0),
                'FM' || RPAD('0', GREATEST(p_longitud - p_decimales - 1,1), '0') || '0.' || RPAD('0',p_decimales,'0')),
            p_longitud, '0');
    END IF;

    RETURN v_resultado;
END format_number;
/

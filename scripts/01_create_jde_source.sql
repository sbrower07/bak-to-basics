/*
  Bak to Basics: JD Edwards-style tables with generated fake data (PostgreSQL).

  Creates three simplified JDE tables in schema proddta of the database you run it in:
    f0101  Address Book Master   (customers, suppliers, employees)
    f4101  Item Master
    f4211  Sales Order Detail    (4 lines per order, linked to f0101 and f4101)

  Safe to re-run: it drops and rebuilds the three tables each time, all in one transaction.
  The data is repeatable: the same settings produce the same rows every run.

  Change the row counts in the CONFIG section below.

  JDE habits copied on purpose:
    - Cryptic column names with a table prefix (ab..., im..., sd...)
      (Postgres lowercases unquoted names, so you query aban8, not ABAN8)
    - Fixed-width CHAR columns padded with spaces, blanks instead of NULLs
    - Business unit right-justified with leading spaces
    - Dates stored as Julian numbers, CYYDDD (C = century since 1900, YY = year, DDD = day of year)
    - Times stored as numbers, HHMMSS
    - 0 in a date column means "no date"
    - Amounts stored as whole numbers with implied decimals (this demo uses 2 implied decimals
      for quantity and extended amount, and 4 for unit price)
    - No real foreign keys: the links between tables are by convention only

  f0101 also gets some deliberately bad rows (see bad_row_pct, plus 4 planted rows) so your
  demo has messy data to clean up, reject, or log.

  Run it with psql, for example:
    psql -U postgres -v ON_ERROR_STOP=1 -f 01_create_jde_source.sql
*/

SET client_min_messages = warning;   -- hide "table does not exist, skipping" notices

BEGIN;

/* ---------------------------------------------------------------------------
   CONFIG: change these numbers to make more or less data
   bad_row_pct = roughly what percent of f0101 rows get a problem (blank name,
   impossible Julian date, or unknown search type)
--------------------------------------------------------------------------- */
DROP TABLE IF EXISTS pg_temp.jde_config;
CREATE TEMP TABLE jde_config AS
SELECT 500  AS address_rows,
       100  AS item_rows,
       2000 AS order_lines,
       3    AS bad_row_pct;

/* ---------------------------------------------------------------------------
   Repeatable "random" number from a row number and a salt: 0 to 999999.
   Built on md5 so the same inputs always give the same output on any Postgres.
   Lives in the temp schema, so nothing is left behind after the session ends.
--------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION pg_temp.rnd(n integer, salt integer)
RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
    SELECT (('x' || substr(md5(n::text || ':' || salt::text), 1, 7))::bit(28)::integer) % 1000000
$$;

/* ---------------------------------------------------------------------------
   TABLES
--------------------------------------------------------------------------- */
CREATE SCHEMA IF NOT EXISTS proddta;

DROP TABLE IF EXISTS proddta.f4211;
DROP TABLE IF EXISTS proddta.f4101;
DROP TABLE IF EXISTS proddta.f0101;

CREATE TABLE proddta.f0101 (
    aban8   numeric(8,0) NOT NULL,            -- Address number (key)
    abalky  char(20)     NOT NULL DEFAULT '', -- Alternate key
    abtax   char(20)     NOT NULL DEFAULT '', -- Tax ID
    abalph  char(40)     NOT NULL DEFAULT '', -- Alpha name
    abdc    char(40)     NOT NULL DEFAULT '', -- Description (compressed)
    abmcu   char(12)     NOT NULL DEFAULT '', -- Business unit (right-justified)
    abat1   char(3)      NOT NULL DEFAULT '', -- Search type (E, C, V ...)
    ablngp  char(2)      NOT NULL DEFAULT '', -- Language
    abcm    char(2)      NOT NULL DEFAULT '', -- Credit message
    abac01  char(3)      NOT NULL DEFAULT '', -- Category code 01
    abuser  char(10)     NOT NULL DEFAULT '', -- User ID
    abpid   char(10)     NOT NULL DEFAULT '', -- Program ID
    abupmj  numeric(6,0) NOT NULL DEFAULT 0,  -- Date updated (Julian CYYDDD)
    abjobn  char(10)     NOT NULL DEFAULT '', -- Workstation ID
    abupmt  numeric(6,0) NOT NULL DEFAULT 0,  -- Time updated (HHMMSS)
    CONSTRAINT pk_f0101 PRIMARY KEY (aban8)
);

CREATE TABLE proddta.f4101 (
    imitm   numeric(8,0) NOT NULL,            -- Item number (key)
    imlitm  char(25)     NOT NULL DEFAULT '', -- 2nd item number
    imdsc1  char(30)     NOT NULL DEFAULT '', -- Description
    imsrp1  char(3)      NOT NULL DEFAULT '', -- Sales catalog section
    imuom1  char(2)      NOT NULL DEFAULT '', -- Primary unit of measure
    imstkt  char(1)      NOT NULL DEFAULT '', -- Stocking type
    imupmj  numeric(6,0) NOT NULL DEFAULT 0,  -- Date updated (Julian CYYDDD)
    imtday  numeric(6,0) NOT NULL DEFAULT 0,  -- Time updated (HHMMSS)
    CONSTRAINT pk_f4101 PRIMARY KEY (imitm)
);

CREATE TABLE proddta.f4211 (
    sddoco  numeric(8,0)  NOT NULL,            -- Order number
    sddcto  char(2)       NOT NULL DEFAULT '', -- Order type
    sdlnid  numeric(6,0)  NOT NULL,            -- Line number (1000 = line 1)
    sdan8   numeric(8,0)  NOT NULL DEFAULT 0,  -- Customer address number (-> f0101)
    sditm   numeric(8,0)  NOT NULL DEFAULT 0,  -- Item number (-> f4101)
    sdlitm  char(25)      NOT NULL DEFAULT '', -- 2nd item number
    sddsc1  char(30)      NOT NULL DEFAULT '', -- Description
    sduorg  numeric(15,0) NOT NULL DEFAULT 0,  -- Quantity ordered (2 implied decimals)
    sduprc  numeric(15,0) NOT NULL DEFAULT 0,  -- Unit price (4 implied decimals)
    sdaexp  numeric(15,0) NOT NULL DEFAULT 0,  -- Extended price (2 implied decimals)
    sduom   char(2)       NOT NULL DEFAULT '', -- Unit of measure
    sdcrcd  char(3)       NOT NULL DEFAULT '', -- Currency code
    sdlttr  char(3)       NOT NULL DEFAULT '', -- Last status
    sdnxtr  char(3)       NOT NULL DEFAULT '', -- Next status
    sdtrdj  numeric(6,0)  NOT NULL DEFAULT 0,  -- Order date (Julian CYYDDD)
    sddrqj  numeric(6,0)  NOT NULL DEFAULT 0,  -- Requested date (Julian CYYDDD)
    sdupmj  numeric(6,0)  NOT NULL DEFAULT 0,  -- Date updated (Julian CYYDDD)
    sdupmt  numeric(6,0)  NOT NULL DEFAULT 0,  -- Time updated (HHMMSS)
    CONSTRAINT pk_f4211 PRIMARY KEY (sddoco, sddcto, sdlnid)
);

/* ---------------------------------------------------------------------------
   F0101 ADDRESS BOOK
   r1..r10 are repeatable pseudo-random numbers (0 to 999999) for each row.
   ty  = search type: about 20% employees, 40% customers, 40% suppliers
   bad = problem flag: 0 = clean, 1 = blank name, 2 = impossible Julian date, 3 = unknown search type
--------------------------------------------------------------------------- */
INSERT INTO proddta.f0101
    (aban8, abalky, abtax, abalph, abdc, abmcu, abat1, ablngp, abcm, abac01, abuser, abpid, abupmj, abjobn, abupmt)
SELECT
    100000 + s.n,
    'A' || lpad(s.n::text, 6, '0'),
    CASE WHEN ty.t = 'E' THEN ''
         ELSE lpad((s.r4 % 100)::text, 2, '0') || '-' || lpad(((s.r5::bigint * 7) % 10000000)::text, 7, '0') END,
    nm.name,
    left(nm.name, 20),
    lpad((ARRAY['1000','2000','3000'])[s.r6 % 3 + 1], 12),
    CASE WHEN bd.bad = 3 THEN 'Z' ELSE ty.t END,
    'E',
    CASE WHEN s.r9 % 20 = 0 THEN 'H' ELSE '' END,
    CASE WHEN ty.t = 'E' THEN '' ELSE (ARRAY['001','002','003'])[s.r9 % 3 + 1] END,
    (ARRAY['JDEUSER','MSMITH','RJONES','HRADMIN'])[s.r7 % 4 + 1],
    'P01012',
    CASE WHEN bd.bad = 2 THEN (extract(year FROM dt.d)::int - 1900) * 1000 + 400   -- day 400 does not exist
         WHEN s.r10 % 50 = 0 THEN 0                                                 -- 0 = no date, valid in JDE
         ELSE (extract(year FROM dt.d)::int - 1900) * 1000 + extract(doy FROM dt.d)::int END,
    'WSJDE0' || (s.r8 % 3 + 1)::text,
    (s.r3 % 24) * 10000 + (s.r4 % 60) * 100 + (s.r5 % 60)
FROM (
    SELECT n,
           pg_temp.rnd(n, 1) AS r1,  pg_temp.rnd(n, 2) AS r2,  pg_temp.rnd(n, 3) AS r3,
           pg_temp.rnd(n, 4) AS r4,  pg_temp.rnd(n, 5) AS r5,  pg_temp.rnd(n, 6) AS r6,
           pg_temp.rnd(n, 7) AS r7,  pg_temp.rnd(n, 8) AS r8,  pg_temp.rnd(n, 9) AS r9,
           pg_temp.rnd(n, 10) AS r10
    FROM generate_series(1, (SELECT address_rows FROM pg_temp.jde_config)) AS n
) s
CROSS JOIN pg_temp.jde_config c
CROSS JOIN LATERAL (SELECT CASE WHEN s.r2 % 10 < 2 THEN 'E' WHEN s.r2 % 10 < 6 THEN 'C' ELSE 'V' END AS t) ty
CROSS JOIN LATERAL (SELECT CASE WHEN s.r10 % 100 < c.bad_row_pct THEN 1 + s.r1 % 3 ELSE 0 END AS bad) bd
CROSS JOIN LATERAL (
    SELECT CASE
        WHEN bd.bad = 1 THEN ''
        WHEN ty.t = 'E' THEN
            (ARRAY['SMITH','GARCIA','JOHNSON','PATEL','WILLIAMS','NGUYEN','BROWN','KIM','JONES',
                   'MARTINEZ','DAVIS','LEE','MILLER','WILSON','ANDERSON'])[s.r2 % 15 + 1]
            || ', ' ||
            (ARRAY['JAMES','MARIA','ROBERT','LINDA','DAVID','SUSAN','CARLOS','PRIYA','MICHAEL',
                   'ANGELA','WEI','OLIVIA','DANIEL','FATIMA','KEVIN'])[s.r1 % 15 + 1]
        ELSE
            (ARRAY['ACME','BLUE RIDGE','HARBOR','NORTHSTAR','SUMMIT','EASTSIDE','DELTA','PINNACLE',
                   'GREENFIELD','LAKESHORE','IRONWOOD','CASCADE','REDWOOD','SILVERLINE','OAKFIELD'])[s.r3 % 15 + 1]
            || ' ' ||
            (ARRAY['INDUSTRIAL SUPPLY','MANUFACTURING','FREIGHT LINES','FOODS INC','ELECTRIC',
                   'PACKAGING CO','LOGISTICS LLC','HOSPITAL','CONSTRUCTION','CHEMICAL CORP',
                   'PLASTICS','MACHINE WORKS'])[s.r4 % 12 + 1]
        END AS name
) nm
CROSS JOIN LATERAL (SELECT current_date - (s.r2 % 730) AS d) dt;

-- Four planted rows so the demo always has bad data to catch
INSERT INTO proddta.f0101
    (aban8, abalky, abtax, abalph, abdc, abmcu, abat1, ablngp, abcm, abac01, abuser, abpid, abupmj, abjobn, abupmt)
VALUES
    (900001, 'BADD900001', '', 'BAD DATE EXAMPLE',    'BAD DATE',     lpad('1000', 12), 'V', 'E', '', '', 'JDEUSER', 'P01012', 125400, 'WSJDE01', 90000),  -- impossible Julian date
    (900002, 'BLNK900002', '', '',                    '',             lpad('1000', 12), 'C', 'E', '', '', 'JDEUSER', 'P01012', 125050, 'WSJDE01', 90000),  -- blank name
    (0,      'ZERO000000', '', 'ZERO KEY TEST',       'ZERO KEY',     lpad('1000', 12), 'C', 'E', '', '', 'JDEUSER', 'P01012', 125050, 'WSJDE01', 90000),  -- address number 0
    (900004, 'UNKN900004', '', 'UNKNOWN TYPE EXAMPLE','UNKNOWN TYPE', lpad('1000', 12), 'Z', 'E', '', '', 'JDEUSER', 'P01012', 125280, 'WSJDE01', 100000); -- unknown search type (warning)

/* ---------------------------------------------------------------------------
   F4101 ITEM MASTER
--------------------------------------------------------------------------- */
INSERT INTO proddta.f4101 (imitm, imlitm, imdsc1, imsrp1, imuom1, imstkt, imupmj, imtday)
SELECT
    200000 + s.n,
    'ITM-' || lpad(s.n::text, 6, '0'),
    (ARRAY['HEX BOLT','FLANGE NUT','STEEL PLATE','COPPER PIPE','PVC FITTING','SAFETY GLOVES',
           'LED LAMP','CONVEYOR BELT','BEARING','GASKET','HYDRAULIC HOSE','AIR FILTER'])[s.r1 % 12 + 1]
    || ' ' ||
    (ARRAY['1/4 IN','1/2 IN','3/4 IN','1 IN','2 IN','SMALL','MEDIUM','LARGE','HD','STD'])[s.r2 % 10 + 1],
    (ARRAY['A01','A02','A03','A04','A05'])[s.r3 % 5 + 1],
    (ARRAY['EA','BX','FT'])[s.r4 % 3 + 1],
    'S',
    (extract(year FROM dt.d)::int - 1900) * 1000 + extract(doy FROM dt.d)::int,
    (s.r6 % 24) * 10000 + (s.r7 % 60) * 100 + (s.r8 % 60)
FROM (
    SELECT n,
           pg_temp.rnd(n, 21) AS r1, pg_temp.rnd(n, 22) AS r2, pg_temp.rnd(n, 23) AS r3,
           pg_temp.rnd(n, 24) AS r4, pg_temp.rnd(n, 25) AS r5, pg_temp.rnd(n, 26) AS r6,
           pg_temp.rnd(n, 27) AS r7, pg_temp.rnd(n, 28) AS r8
    FROM generate_series(1, (SELECT item_rows FROM pg_temp.jde_config)) AS n
) s
CROSS JOIN LATERAL (SELECT current_date - (s.r5 % 730) AS d) dt;

/* ---------------------------------------------------------------------------
   F4211 SALES ORDER DETAIL
   4 lines per order. The customer and dates are the same for every line of an order.
   Customers are picked from clean f0101 rows with search type C; items from f4101.
--------------------------------------------------------------------------- */
DROP TABLE IF EXISTS pg_temp.jde_cust;
DROP TABLE IF EXISTS pg_temp.jde_items;

CREATE TEMP TABLE jde_cust AS
SELECT row_number() OVER (ORDER BY aban8) AS id, aban8
FROM proddta.f0101
WHERE abat1 = 'C' AND trim(abalph) <> '' AND aban8 > 0;

CREATE TEMP TABLE jde_items AS
SELECT row_number() OVER (ORDER BY imitm) AS id, imitm, imlitm, imdsc1, imuom1
FROM proddta.f4101;

INSERT INTO proddta.f4211
    (sddoco, sddcto, sdlnid, sdan8, sditm, sdlitm, sddsc1, sduorg, sduprc, sdaexp,
     sduom, sdcrcd, sdlttr, sdnxtr, sdtrdj, sddrqj, sdupmj, sdupmt)
SELECT
    500000 + o.oi,
    'SO',
    ((s.n - 1) % 4 + 1) * 1000,
    cu.aban8,
    it.imitm,
    it.imlitm,
    it.imdsc1,
    qty.q * 100,                    -- quantity, 2 implied decimals
    px.cents * 100,                 -- unit price, 4 implied decimals
    qty.q * px.cents,               -- extended price in cents, 2 implied decimals
    it.imuom1,
    'USD',
    st.last_status,
    st.next_status,
    jl.jo,
    jl.jr,
    jl.jo,
    (s.r6 % 24) * 10000 + (s.r7 % 60) * 100 + (s.r8 % 60)
FROM (
    SELECT n,
           pg_temp.rnd(n, 31) AS r1, pg_temp.rnd(n, 32) AS r2, pg_temp.rnd(n, 33) AS r3,
           pg_temp.rnd(n, 34) AS r4, pg_temp.rnd(n, 35) AS r5, pg_temp.rnd(n, 36) AS r6,
           pg_temp.rnd(n, 37) AS r7, pg_temp.rnd(n, 38) AS r8
    FROM generate_series(1, (SELECT order_lines FROM pg_temp.jde_config)) AS n
) s
CROSS JOIN LATERAL (SELECT (s.n - 1) / 4 AS oi) o
JOIN pg_temp.jde_cust  cu ON cu.id = (o.oi::bigint * 7919) % (SELECT count(*) FROM pg_temp.jde_cust)  + 1
JOIN pg_temp.jde_items it ON it.id = s.r5 % (SELECT count(*) FROM pg_temp.jde_items) + 1
CROSS JOIN LATERAL (SELECT 1 + s.r3 % 50 AS q) qty
CROSS JOIN LATERAL (SELECT 100 + s.r4 % 20000 AS cents) px          -- $1.00 to $200.99
CROSS JOIN LATERAL (SELECT CASE s.r1 % 3 WHEN 0 THEN '520' WHEN 1 THEN '540' ELSE '560' END AS last_status,
                           CASE s.r1 % 3 WHEN 0 THEN '540' WHEN 1 THEN '560' ELSE '580' END AS next_status) st
CROSS JOIN LATERAL (SELECT current_date - ((o.oi * 31) % 365) AS d) dt
CROSS JOIN LATERAL (SELECT (extract(year FROM dt.d)::int - 1900) * 1000 + extract(doy FROM dt.d)::int AS jo,
                           (extract(year FROM dt.d + 7)::int - 1900) * 1000 + extract(doy FROM dt.d + 7)::int AS jr) jl;

COMMIT;

/* ---------------------------------------------------------------------------
   SUMMARY
--------------------------------------------------------------------------- */
SELECT 'f0101 Address Book'       AS table_name, count(*) AS row_count FROM proddta.f0101
UNION ALL
SELECT 'f4101 Item Master',       count(*) FROM proddta.f4101
UNION ALL
SELECT 'f4211 Sales Order Lines', count(*) FROM proddta.f4211;

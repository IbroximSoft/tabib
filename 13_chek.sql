-- ============================================================
--  13_chek.sql — toʻlov cheki va toʻlov tarixi
--  01, 03, 05, 06, 08, 09, 10, 11, 12 dan KEYIN. Idempotent.
--
--  Nima qoʻshiladi:
--   1. tolov_qosh() — endi chek raqamini (tolov_id) qaytaradi,
--      huquq tekshiruvi bor va kassir avtomatik yoziladi.
--      Shu bilan "toʻlov qabul qilindi -> chek chiqdi" zanjiri
--      uziladigan joyi qolmaydi.
--   2. chek() — chek qogʻoziga kerak boʻlgan hamma narsa:
--      bemor, xona, koyka, kunlik narx, kurs kuni, toʻlov,
--      qolgan qarz, kassir.
--   3. v_tolovlar ga chek uchun kerak ustunlar.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.v_koykalar') IS NULL THEN
    RAISE EXCEPTION 'Avval 12_xonalar_korinishi.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. TO'LOV QABUL QILISH
--    Eski versiya faqat qolgan qarzni qaytarardi — chek raqami
--    bilinmasdi va chekni darhol chiqarib boʻlmasdi.
--    Huquq tekshiruvi ham yoʻq edi: kuzatuvchi ham RPC orqali
--    toʻlov kiritishi mumkin edi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS tolov_qosh(int, numeric, tolov_usuli, text);
DROP FUNCTION IF EXISTS tolov_qosh(int, numeric, tolov_usuli, text, text);

CREATE FUNCTION tolov_qosh(
  p_yotqizish int,
  p_summa     numeric,
  p_usuli     tolov_usuli DEFAULT 'naqd',
  p_kim       text DEFAULT NULL,
  p_izoh      text DEFAULT NULL
) RETURNS TABLE (tolov_id int, qolgan_qarz numeric, chek_raqam text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_id int;
BEGIN
  PERFORM huquq_tekshir(
    ARRAY['super_admin','buxgalter','administrator']::rol_turi[],
    'toʻlov qabul qilish');

  IF p_summa IS NULL OR p_summa <= 0 THEN
    RAISE EXCEPTION 'Toʻlov summasi noldan katta boʻlishi kerak.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM yotqizishlar WHERE id = p_yotqizish) THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO tolovlar (yotqizish_id, summa, usuli, kim, izoh)
  VALUES (p_yotqizish, p_summa, p_usuli,
          COALESCE(NULLIF(p_kim,''), joriy_fish()), p_izoh)
  RETURNING id INTO v_id;

  RETURN QUERY
  SELECT v_id, qarz(p_yotqizish), 'CHK-' || lpad(v_id::text, 6, '0');
END $$;

-- ------------------------------------------------------------
-- 2. CHEK — qogʻozga chiqadigan hamma maʼlumot
--    Ustunlar oʻzgargani uchun avval oʻchiriladi (42P13).
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS chek(int);

CREATE FUNCTION chek(p_tolov int)
RETURNS TABLE (
  chek_raqam    text,
  tolov_id      int,
  tolov_vaqti   timestamptz,
  sana          date,

  fish          text,
  familiya      text,
  ism           text,
  yosh          int,
  telefon       text,
  roli          shaxs_roli,

  bolim         text,
  xona          text,
  koyka         smallint,

  kirish_sana   date,
  reja_chiqish  date,
  kurs_kun      int,
  yotgan_kun    int,

  kunlik        numeric,      -- bir kunlik narx (chek qogʻozidagi kabi)
  kurs_summa    numeric,      -- toʻliq kurs
  xona_summa    numeric,
  umumiy        numeric,      -- hozirgi haqiqiy hisob
  summa         numeric,      -- shu toʻlov
  usuli         tolov_usuli,
  tolangan      numeric,      -- jami toʻlangan
  qolgan_qarz   numeric,
  kassir        text
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    'CHK-' || lpad(t.id::text, 6, '0'),
    t.id,
    t.yaratilgan,
    t.sana,

    b.familiya || ' ' || b.ism,
    b.familiya, b.ism,
    bemor_yoshi(b),
    b.telefon,
    y.roli,

    COALESCE(bo.nomi, '—'),
    COALESCE(x.raqam, '—'),
    k.raqam,

    y.kirish_sana,
    y.reja_chiqish,
    (SELECT qiymat::int FROM tariflar WHERE kalit = 'kurs_kun'),
    (COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, current_date)
       - y.kirish_sana + 1),

    CASE WHEN (SELECT qiymat FROM tariflar WHERE kalit = 'kurs_kun') > 0
         THEN round((y.summa + y.xona_summa)
                    / (SELECT qiymat FROM tariflar WHERE kalit = 'kurs_kun'))
    END,
    y.summa + y.xona_summa,
    y.xona_summa,
    hisob(y.id),
    t.summa,
    t.usuli,
    tolangan(y.id),
    qarz(y.id),
    COALESCE(t.kim, '—')
  FROM tolovlar t
    JOIN yotqizishlar y ON y.id = t.yotqizish_id
    JOIN bemorlar b     ON b.id = y.bemor_id
    LEFT JOIN koykalar k ON k.id = y.koyka_id
    LEFT JOIN xonalar x  ON x.id = k.xona_id
    LEFT JOIN bolimlar bo ON bo.id = x.bolim_id
  WHERE t.id = p_tolov;
$$;

-- ------------------------------------------------------------
-- 3. TO'LOV TARIXI — bemor kartasidagi roʻyxat uchun
--    v_tolovlar da yotqizish_id bor, lekin kirish sanasi va
--    koyka yoʻq edi — chekni qayta chiqarishda kerak boʻladi.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_tolovlar CASCADE;
CREATE VIEW v_tolovlar
WITH (security_invoker = on) AS
SELECT
  t.id                       AS tolov_id,
  'CHK-' || lpad(t.id::text, 6, '0') AS chek_raqam,
  t.sana, t.yaratilgan       AS vaqt,
  t.summa, t.usuli,
  COALESCE(t.kim, '—')       AS kassir,
  t.izoh,
  y.id                       AS yotqizish_id,
  b.familiya || ' ' || b.ism AS fish,
  b.telefon,
  COALESCE(x.raqam, '—')     AS xona,
  k.raqam                    AS koyka,
  bo.nomi                    AS bolim,
  y.kirish_sana,
  y.reja_chiqish,
  y.summa + y.xona_summa     AS kurs_summa,
  hisob(y.id)                AS umumiy,
  tolangan(y.id)             AS tolangan,
  qarz(y.id)                 AS qolgan_qarz
FROM tolovlar t
  JOIN yotqizishlar y   ON y.id = t.yotqizish_id
  JOIN bemorlar b       ON b.id = y.bemor_id
  LEFT JOIN koykalar k  ON k.id = y.koyka_id
  LEFT JOIN xonalar x   ON x.id = k.xona_id
  LEFT JOIN bolimlar bo ON bo.id = x.bolim_id;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

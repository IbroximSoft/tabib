-- ============================================================
--  15_hisobotlar.sql — hisobot ekrani uchun
--  01, 03, 05, 06, 08..14 dan KEYIN. Idempotent.
--
--  05_hisobotlar.sql da hisobot_kunlik(), hisobot_moliya(),
--  hisobot_kassir() va v_bolim_hisoboti bor — ular saqlanadi.
--  Bu yerda faqat yetishmayotgani qo'shiladi:
--
--   1. hisobot_xulosa()  — ekrandagi kartalar uchun bitta qator
--   2. hisobot_bemorlar() — oraliqdagi bemorlar jadvali
--   3. hisobot_ovqat()    — ovqat hisobi sana oralig'i bo'yicha
--                           (mijozning asosiy muammosi shu edi)
--   4. hisobot_bron()     — bronlar kesimi
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.v_bronlar') IS NULL THEN
    RAISE EXCEPTION 'Avval 14_bronlar.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. XULOSA — ekran tepasidagi kartalar
--    hisobot_moliya() nom/qiymat ro'yxati qaytaradi, u chop
--    etishga qulay. Ekranga esa ustunli bitta qator kerak.
-- ------------------------------------------------------------
-- DIQQAT: 24_qaytarish.sql bu funksiyaga "qaytarilgan" ustunini
-- qo'shadi va tushumni qaytarishlardan tozalaydi. U ishga tushgan
-- bazada bu yerdagi eski variant uni bosib ketmasin.
DO $blokx$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname='qaytarish_ornatildi') THEN
  RAISE NOTICE '24_qaytarish.sql ishga tushgan — hisobot_xulosa() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
DROP FUNCTION IF EXISTS hisobot_xulosa(date, date);

CREATE FUNCTION hisobot_xulosa(p_dan date, p_gacha date)
RETURNS TABLE (
  tushum        numeric,   -- oraliqdagi jami to'lov
  naqd          numeric,
  karta         numeric,
  otkazma       numeric,
  tolov_soni    bigint,
  yangi_bemor   bigint,    -- oraliqda kelganlar
  chiqqan       bigint,    -- oraliqda ketganlar
  ortacha_kun   numeric,   -- chiqqanlarning o'rtacha yotgan kuni
  hozir_yotibdi bigint,
  qarz_jami     numeric,
  qarzdor_soni  bigint,
  bron_kutilyapti bigint,
  ortiqcha_jami numeric,   -- hisobdan ortiq to'langan pul (qaytarilishi kerak)
  ortiqcha_soni bigint
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $t$
  SELECT
    (SELECT COALESCE(sum(summa),0) FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha),
    (SELECT COALESCE(sum(summa),0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha AND usuli='naqd'),
    (SELECT COALESCE(sum(summa),0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha AND usuli='karta'),
    (SELECT COALESCE(sum(summa),0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha AND usuli='otkazma'),
    (SELECT count(*) FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha),
    (SELECT count(*) FROM yotqizishlar
      WHERE kirish_sana BETWEEN p_dan AND p_gacha AND holat <> 'bekor'),
    (SELECT count(*) FROM yotqizishlar
      WHERE (haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
            BETWEEN p_dan AND p_gacha),
    (SELECT round(AVG((haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
                      - kirish_sana + 1), 1)
       FROM yotqizishlar
      WHERE (haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
            BETWEEN p_dan AND p_gacha),
    (SELECT count(*) FROM yotqizishlar WHERE holat='yotmoqda'),
    (SELECT COALESCE(sum(qarz),0) FROM v_qarzdorlar),
    (SELECT count(*) FROM v_qarzdorlar),
    (SELECT count(*) FROM bronlar WHERE holat='kutilmoqda'),
    -- Bemor erta ketsa hisob kamayadi, lekin to'langan pul joyida
    -- qoladi — farq qaytarilishi kerak. Shu paytgacha hech qayerda
    -- ko'rinmasdi.
    (SELECT COALESCE(sum(GREATEST(0, tolangan(y.id) - hisob(y.id))), 0)
       FROM yotqizishlar y WHERE y.holat <> 'bekor'),
    (SELECT count(*) FROM yotqizishlar y
      WHERE y.holat <> 'bekor' AND tolangan(y.id) > hisob(y.id));
$t$;
$f$;
END $blokx$;

-- ------------------------------------------------------------
-- 2. ORALIQDAGI BEMORLAR
--    Kim kelgan, qancha yotgan, qancha to'lagan, qarzi bormi.
-- ------------------------------------------------------------
-- DIQQAT: 16_tashxis.sql bu funksiyaga "tashxis" ustunini qo'shadi.
-- U ishga tushgan bazada bu yerdagi variant uni bosib ketmasin.
DO $blokh$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='yotqizishlar'
              AND column_name='tashxis') THEN
  RAISE NOTICE '16_tashxis.sql ishga tushgan — hisobot_bemorlar() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
DROP FUNCTION IF EXISTS hisobot_bemorlar(date, date)
$f$;
EXECUTE $f$
CREATE FUNCTION hisobot_bemorlar(p_dan date, p_gacha date)
RETURNS TABLE (
  yotqizish_id int, fish text, telefon text, jins jins_turi,
  roli shaxs_roli, bolim text, xona text,
  kirish_sana date, reja_chiqish date, haqiqiy_chiqish date,
  yotgan_kun int, holat yotqizish_holati,
  kurs_summa numeric, umumiy numeric, tolangan numeric, qarz numeric,
  ortiqcha numeric
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    y.id,
    b.familiya || ' ' || b.ism,
    b.telefon, b.jins, y.roli,
    COALESCE(bo.nomi, '—'),
    COALESCE(x.raqam, '—'),
    y.kirish_sana, y.reja_chiqish,
    (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
    (COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, current_date)
       - y.kirish_sana + 1),
    y.holat,
    y.summa + y.xona_summa,
    hisob(y.id), tolangan(y.id), qarz(y.id),
    GREATEST(0, tolangan(y.id) - hisob(y.id))
  FROM yotqizishlar y
    JOIN bemorlar b       ON b.id = y.bemor_id
    LEFT JOIN koykalar k  ON k.id = y.koyka_id
    LEFT JOIN xonalar x   ON x.id = k.xona_id
    LEFT JOIN bolimlar bo ON bo.id = x.bolim_id
  WHERE y.holat <> 'bekor'
    AND y.kirish_sana <= p_gacha
    AND COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                 y.reja_chiqish) >= p_dan
  ORDER BY y.kirish_sana DESC, b.familiya;
$$
$f$;
END $blokh$;

-- ------------------------------------------------------------
-- 3. OVQAT HISOBI — SANA ORALIG'I BO'YICHA
--
--    Mijozning asosiy shikoyati shu edi: bemor rejadagi sanadan
--    erta ketsa, tizim uni hali yotibdi deb sanardi va shifokor
--    ovqatni ortiqcha hisoblardi.
--
--    Bu yerda kun bo'yicha kim ROSTDAN yotgani sanaladi:
--    haqiqiy chiqish bo'lsa — o'sha kungacha, bo'lmasa rejagacha.
--
--    KIM SANALADI: bemor, farzand va qarovchi — UCHALASI ham.
--    Ustunlar alohida ko'rsatiladi (kim nechta ekani ko'rinsin
--    uchun), lekin jami_kishi, nonushta, tushlik, kechki va
--    jami_porsiya hammasini birga sanaydi. Oshxonaga beriladigan
--    raqam shu.
--
--    PORSIYA QOIDASI
--      nonushta — o'sha kuni KELGANLAR sanalmaydi (kelgan kuni
--                 nonushta bo'lmaydi);
--      tushlik  — o'sha kuni yotganlarning hammasi;
--      kechki   — o'sha kuni KETGANLAR sanalmaydi.
--    Shu sababli uch raqam bir xil chiqmaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS hisobot_ovqat(date, date);

CREATE FUNCTION hisobot_ovqat(p_dan date, p_gacha date)
RETURNS TABLE (
  sana date,
  bemor bigint,        -- rol = bemor
  farzand bigint,
  qarovchi bigint,
  jami_kishi bigint,
  nonushta bigint,     -- o'sha kuni kelganlar nonushta qilmaydi
  tushlik bigint,
  kechki bigint,       -- o'sha kuni ketganlar kechki ovqat yemaydi
  jami_porsiya bigint
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  WITH kunlar AS (
    SELECT g::date AS d FROM generate_series(p_dan, p_gacha, interval '1 day') g
  ),
  faol AS (
    SELECT k.d, y.roli, y.kirish_sana,
           COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                    y.reja_chiqish) AS tugash
    FROM kunlar k
      JOIN yotqizishlar y
        ON y.holat <> 'bekor'
       AND y.kirish_sana <= k.d
       AND COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                    y.reja_chiqish) >= k.d
  )
  SELECT
    k.d,
    count(f.*) FILTER (WHERE f.roli = 'bemor'),
    count(f.*) FILTER (WHERE f.roli = 'farzand'),
    count(f.*) FILTER (WHERE f.roli = 'qarovchi'),
    count(f.*),
    count(f.*) FILTER (WHERE f.kirish_sana <> k.d),
    count(f.*),
    count(f.*) FILTER (WHERE f.tugash <> k.d),
    count(f.*) FILTER (WHERE f.kirish_sana <> k.d)
      + count(f.*)
      + count(f.*) FILTER (WHERE f.tugash <> k.d)
  FROM kunlar k LEFT JOIN faol f ON f.d = k.d
  GROUP BY k.d
  ORDER BY k.d;
$$;

-- ------------------------------------------------------------
-- 4. BRONLAR KESIMI
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS hisobot_bron(date, date);

CREATE FUNCTION hisobot_bron(p_dan date, p_gacha date)
RETURNS TABLE (
  holat text, soni bigint, kishi numeric
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT v.holat_matn, count(*), COALESCE(sum(v.kishi), 0)
  FROM v_bronlar v
  WHERE v.kirish BETWEEN p_dan AND p_gacha
  GROUP BY v.holat_matn
  ORDER BY 2 DESC;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

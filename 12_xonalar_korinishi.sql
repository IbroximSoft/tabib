-- ============================================================
--  12_xonalar_korinishi.sql
--  01, 03, 05, 06, 08, 09, 10, 11 dan KEYIN. Idempotent.
--
--  Xonalar ekrani uchun maʼlumot manbai:
--   1. v_koykalar   — har bir koyka boʻyicha bitta qator
--                     (kim yotibdi, qaysi boʻlim, jinsi, narxi)
--   2. v_xona_holati — boʻlim, taʼmir holati va bron qoʻshildi
--   3. xona_tamir()  — xonani taʼmirga qoʻyish / qaytarish
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
--   Fayllar tartib bilan ishga tushirilishi kerak. Biror
--   oldingisi qolib ketgan bo'lsa, tushunarli xabar beramiz.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.xona_turlari') IS NULL THEN
    RAISE EXCEPTION 'Avval 11_xona_turlari.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. HAR BIR KOYKA — bitta qator
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_koykalar
WITH (security_invoker = on) AS
SELECT
  k.id                AS koyka_id,
  k.raqam             AS koyka,
  x.id                AS xona_id,
  x.raqam             AS xona,
  x.turi,
  x.tamirlashda,
  bo.id               AS bolim_id,
  bo.nomi             AS bolim,
  bo.jins             AS bolim_jinsi,
  bo.tartib           AS bolim_tartib,
  COALESCE(t.narx, x.narx, 0) AS xona_narx,

  y.id                AS yotqizish_id,
  y.roli,
  y.asosiy_id,
  y.kirish_sana,
  y.reja_chiqish,
  (y.id IS NOT NULL AND y.reja_chiqish < current_date) AS tasdiqlanmagan,
  CASE WHEN y.id IS NOT NULL
       THEN (current_date - y.kirish_sana + 1) END      AS yotgan_kun,
  b.familiya || ' ' || b.ism AS fish,
  b.jins,
  b.telefon,
  CASE WHEN y.id IS NOT NULL THEN qarz(y.id) END        AS qarz
FROM koykalar k
  JOIN xonalar x        ON x.id = k.xona_id
  JOIN bolimlar bo      ON bo.id = x.bolim_id
  LEFT JOIN xona_turlari t ON t.nomi = x.turi
  LEFT JOIN yotqizishlar y ON y.koyka_id = k.id AND y.holat = 'yotmoqda'
  LEFT JOIN bemorlar b     ON b.id = y.bemor_id;

-- ------------------------------------------------------------
-- 2. XONA HOLATI — boʻlim, taʼmir va bron maʼlumoti bilan
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_xona_holati CASCADE;
CREATE VIEW v_xona_holati
WITH (security_invoker = on) AS
SELECT
  x.id, x.raqam,
  bo.id   AS bolim_id,
  bo.nomi AS bolim,
  bo.jins AS bolim_jinsi,
  bo.tartib AS bolim_tartib,
  x.turi,
  COALESCE(t.narx, x.narx, 0) AS narx,
  x.tamirlashda,
  count(DISTINCT k.id)                                   AS sigim,
  count(DISTINCT k.id) FILTER (WHERE y.id IS NOT NULL)   AS band,
  count(DISTINCT y.id)                                   AS faol_yozuv,
  count(DISTINCT y.id) FILTER (WHERE y.reja_chiqish < current_date) AS tasdiqlanmagan,
  -- xonada qaysi jins yotibdi (aralash boʻlimda ikkalasi boʻlishi mumkin)
  CASE WHEN count(DISTINCT b.jins) = 1 THEN min(b.jins::text) END AS xona_jinsi,
  (SELECT count(*) FROM bronlar br
    WHERE br.xona_id = x.id AND br.holat = 'kutilmoqda')  AS bron_soni,
  CASE
    WHEN x.tamirlashda THEN 'tamir'
    WHEN count(DISTINCT k.id) FILTER (WHERE y.id IS NOT NULL) = 0
         AND EXISTS (SELECT 1 FROM bronlar br
                     WHERE br.xona_id = x.id AND br.holat = 'kutilmoqda') THEN 'bron'
    WHEN count(DISTINCT k.id) FILTER (WHERE y.id IS NOT NULL) = 0 THEN 'bosh'
    WHEN count(DISTINCT k.id) FILTER (WHERE y.id IS NOT NULL)
         >= count(DISTINCT k.id) THEN 'toliq'
    ELSE 'qisman'
  END AS holat
FROM xonalar x
  JOIN bolimlar bo ON bo.id = x.bolim_id
  LEFT JOIN xona_turlari t ON t.nomi = x.turi
  LEFT JOIN koykalar k ON k.xona_id = x.id
  LEFT JOIN yotqizishlar y ON y.koyka_id = k.id AND y.holat = 'yotmoqda'
  LEFT JOIN bemorlar b ON b.id = y.bemor_id
GROUP BY x.id, x.raqam, bo.id, bo.nomi, bo.jins, bo.tartib,
         x.turi, t.narx, x.narx, x.tamirlashda;

-- v_umumiy CASCADE bilan o'chgan bo'lishi mumkin — tiklaymiz
CREATE OR REPLACE VIEW v_umumiy
WITH (security_invoker = on) AS
SELECT
  (SELECT count(*) FROM bemorlar)                                       AS jami_bemor,
  (SELECT count(*) FROM yotqizishlar WHERE holat='yotmoqda')            AS hozir_yotmoqda,
  (SELECT count(*) FROM yotqizishlar
     WHERE holat='yotmoqda' AND koyka_id IS NULL)                       AS xonasiz,
  (SELECT count(*) FROM yotqizishlar WHERE kirish_sana=current_date)    AS bugun_keldi,
  (SELECT count(*) FROM yotqizishlar
     WHERE holat='yotmoqda' AND reja_chiqish=current_date)              AS bugun_ketishi_kerak,
  (SELECT count(*) FROM yotqizishlar
     WHERE (haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
           = current_date)                                              AS bugun_ketdi,
  (SELECT count(*) FROM v_tasdiqlanmagan)                               AS tasdiqlanmagan,
  (SELECT count(*) FROM v_xona_holati WHERE holat='bosh')               AS bosh_xona,
  (SELECT count(*) FROM v_xona_holati WHERE holat IN ('qisman','toliq'))AS band_xona,
  (SELECT count(*) FROM bronlar WHERE holat='kutilmoqda')               AS bron,
  (SELECT count(*) FROM v_qarzdorlar)                                   AS qarzdor_soni,
  (SELECT COALESCE(sum(qarz),0) FROM v_qarzdorlar)                      AS qarz_jami,
  (SELECT COALESCE(sum(summa),0) FROM tolovlar WHERE sana=current_date) AS bugungi_tushum,
  (SELECT COALESCE(sum(summa),0) FROM tolovlar
     WHERE sana >= date_trunc('month', current_date)::date)             AS oylik_tushum;

-- ------------------------------------------------------------
-- 3. XONANI TA'MIRGA QO'YISH / QAYTARISH
--    Ichida bemor boʻlsa taʼmirga qoʻyib boʻlmaydi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION xona_tamir(p_xona int, p_tamir boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_band int; v_raqam text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'xona holatini oʻzgartirish');

  SELECT raqam INTO v_raqam FROM xonalar WHERE id = p_xona;
  IF v_raqam IS NULL THEN
    RAISE EXCEPTION 'Xona topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  IF p_tamir THEN
    SELECT count(*) INTO v_band
    FROM yotqizishlar y JOIN koykalar k ON k.id = y.koyka_id
    WHERE k.xona_id = p_xona AND y.holat = 'yotmoqda';
    IF v_band > 0 THEN
      RAISE EXCEPTION '%-xonada % ta bemor yotibdi — taʼmirga qoʻyib boʻlmaydi.', v_raqam, v_band
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  UPDATE xonalar SET tamirlashda = p_tamir WHERE id = p_xona;
  RETURN p_tamir;
END $$;

-- ------------------------------------------------------------
-- 4. XONA QO'SHISH — huquq tekshiruvi bilan
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION xona_qosh(
  p_bolim_id int, p_raqam text, p_turi text, p_sigim int
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_xona int; v_bolim text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'xona qoʻshish');

  IF COALESCE(trim(p_raqam),'') = '' THEN
    RAISE EXCEPTION 'Xona raqamini kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_sigim IS NULL OR p_sigim < 1 OR p_sigim > 20 THEN
    RAISE EXCEPTION 'Koykalar soni 1 dan 20 gacha boʻlishi kerak.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM xonalar WHERE raqam = trim(p_raqam)) THEN
    RAISE EXCEPTION '%-xona allaqachon mavjud.', trim(p_raqam) USING ERRCODE = 'unique_violation';
  END IF;

  SELECT nomi INTO v_bolim FROM bolimlar WHERE id = p_bolim_id;
  IF v_bolim IS NULL THEN
    RAISE EXCEPTION 'Boʻlim tanlanmagan.' USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO xona_turlari (nomi, narx) VALUES (p_turi, 0) ON CONFLICT (nomi) DO NOTHING;

  INSERT INTO xonalar (bolim_id, raqam, turi, narx)
  VALUES (p_bolim_id, trim(p_raqam), p_turi,
          (SELECT narx FROM xona_turlari WHERE nomi = p_turi))
  RETURNING id INTO v_xona;

  INSERT INTO koykalar (xona_id, raqam)
  SELECT v_xona, g FROM generate_series(1, p_sigim) g;

  RETURN v_xona;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

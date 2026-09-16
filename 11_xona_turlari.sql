-- ============================================================
--  11_xona_turlari.sql
--  01, 03, 05, 06, 08, 09, 10 dan KEYIN. Idempotent.
--
--  Mijoz qarorlari:
--   1. Har bir xonani alohida narxlash kerak emas.
--      Narx XONA TURIGA bogʻlanadi: Standart, Oilaviy, Premium...
--      Sozlamalarda har tur uchun bitta son turadi.
--   2. Xona puli har bir MUSTAQIL BEMORGA yoziladi.
--      Farzand va qarovchi xona uchun toʻlamaydi — chunki bemor
--      xonani oʻzi va hamrohi uchun band qiladi.
--      Umumiy palatada ikki begona bemor yotsa — ikkalasi ham
--      toʻlaydi (avval faqat birinchisi toʻlardi).
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
--   Fayllar tartib bilan ishga tushirilishi kerak. Biror
--   oldingisi qolib ketgan bo'lsa, tushunarli xabar beramiz.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.narx_tarixi') IS NULL THEN
    RAISE EXCEPTION 'Avval 09_narx_va_telefon.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
  -- 10 ishga tushgani "kurs_summa" ustuni bo'yicha bilinadi
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'v_yotqizishlar'
                    AND column_name = 'kurs_summa') THEN
    RAISE EXCEPTION 'Avval 10_kunlik_hisob.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. XONA TURLARI VA ULARNING NARXI
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS xona_turlari (
  nomi    text PRIMARY KEY,
  narx    numeric(12,0) NOT NULL DEFAULT 0,
  tartib  smallint NOT NULL DEFAULT 0,
  izoh    text
);

-- Mavjud xonalardagi turlardan toʻldiramiz (narx eng kattasidan olinadi)
INSERT INTO xona_turlari (nomi, narx)
SELECT x.turi, COALESCE(max(x.narx), 0)
FROM xonalar x
WHERE COALESCE(x.turi,'') <> ''
GROUP BY x.turi
ON CONFLICT (nomi) DO NOTHING;

-- Standart har doim boʻlsin
INSERT INTO xona_turlari (nomi, narx, tartib, izoh)
VALUES ('Standart', 3000000, 1, '1 kurs uchun')
ON CONFLICT (nomi) DO NOTHING;

ALTER TABLE xona_turlari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS korish ON xona_turlari;
CREATE POLICY korish ON xona_turlari FOR SELECT USING (joriy_rol() IS NOT NULL);

-- Xonaning turi roʻyxatdagilardan biri boʻlsin
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'xonalar_turi_fk') THEN
    UPDATE xonalar SET turi = 'Standart' WHERE COALESCE(turi,'') = '';
    ALTER TABLE xonalar
      ADD CONSTRAINT xonalar_turi_fk FOREIGN KEY (turi)
      REFERENCES xona_turlari(nomi) ON UPDATE CASCADE;
  END IF;
END $$;

-- Xona narxini turdan olish
CREATE OR REPLACE FUNCTION xona_narxi(p_xona int) RETURNS numeric
LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  SELECT COALESCE(t.narx, x.narx, 0)
  FROM xonalar x LEFT JOIN xona_turlari t ON t.nomi = x.turi
  WHERE x.id = p_xona
$$;

-- ------------------------------------------------------------
-- 2. TUR NARXINI OʻZGARTIRISH (super_admin, buxgalter)
--    xonalar.narx ustuni ham yangilanadi — eski koʻrinishlar
--    bir xil sonni koʻrsatib tursin.
-- ------------------------------------------------------------
DO $bn$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname='buxgalter_toraytirildi') THEN
  RAISE NOTICE '18_buxgalter.sql ishga tushgan — xona_turi_narx() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION xona_turi_narx(p_turi text, p_narx numeric)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_eski numeric;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','buxgalter']::rol_turi[],
                        'xona narxini oʻzgartirish');
  IF p_narx IS NULL OR p_narx < 0 THEN
    RAISE EXCEPTION 'Narx manfiy boʻlishi mumkin emas.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT narx INTO v_eski FROM xona_turlari WHERE nomi = p_turi;
  IF v_eski IS NULL THEN
    INSERT INTO xona_turlari (nomi, narx) VALUES (p_turi, p_narx);
  ELSE
    UPDATE xona_turlari SET narx = p_narx WHERE nomi = p_turi;
  END IF;

  UPDATE xonalar SET narx = p_narx WHERE turi = p_turi;

  INSERT INTO narx_tarixi (tur, nomi, eski, yangi, kim)
  VALUES ('xona_turi', p_turi, v_eski, p_narx, joriy_fish());
  RETURN p_narx;
END $$
$f$;
END $bn$;


-- Eski funksiyalar endi kerak emas: narx xonaga emas, turga bogʻlangan
DROP FUNCTION IF EXISTS xona_narx_ozgartir(int, numeric);
DROP FUNCTION IF EXISTS xona_narx_sigim(int, numeric);

-- ------------------------------------------------------------
-- 3. XONA PULI HAR BIR MUSTAQIL BEMORGA
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bemor_joylashtir(
  p_familiya text, p_ism text, p_jins jins_turi, p_telefon text,
  p_yosh int, p_chet_el boolean, p_roli shaxs_roli,
  p_koyka int, p_kirish date, p_reja_chiqish date,
  p_oldindan numeric DEFAULT 0, p_asosiy int DEFAULT NULL,
  p_bemor_id int DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_bemor int; v_yotqizish int; v_summa numeric; v_xona_summa numeric := 0;
  v_xona int; v_mavjud int; v_raqam text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bemorni ro''yxatga olish');

  IF p_bemor_id IS NOT NULL THEN
    SELECT id INTO v_bemor FROM bemorlar WHERE id = p_bemor_id;
    IF v_bemor IS NULL THEN
      RAISE EXCEPTION 'Bemor topilmadi (id: %).', p_bemor_id;
    END IF;
  ELSE
    v_raqam := regexp_replace(COALESCE(p_telefon,''), '\D', '', 'g');
    IF p_roli = 'bemor' AND v_raqam <> '' THEN
      SELECT b.id INTO v_mavjud FROM bemorlar b
       WHERE NOT b.hamroh AND b.telefon_raqam = v_raqam LIMIT 1;
      IF v_mavjud IS NOT NULL THEN
        RAISE EXCEPTION 'Bu telefon raqami bilan bemor allaqachon roʻyxatda bor. Uning kartasini oching yoki qayta qabul qiling. (bemor_id: %)', v_mavjud
          USING ERRCODE = 'unique_violation';
      END IF;
    END IF;

    INSERT INTO bemorlar (familiya, ism, jins, telefon, yosh, chet_el, fuqaroligi, hamroh)
    VALUES (p_familiya, p_ism, p_jins, p_telefon, p_yosh, p_chet_el,
            CASE WHEN p_chet_el THEN 'Chet el fuqarosi' ELSE 'O''zbekiston' END,
            p_roli <> 'bemor')
    RETURNING id INTO v_bemor;
  END IF;

  v_summa := narx_hisobla(p_yosh, p_chet_el, p_roli);

  -- ⭐ Xona puli: faqat mustaqil bemor toʻlaydi.
  --    Farzand va qarovchi — 0 (bemor xonani ular uchun ham band qilgan).
  IF p_koyka IS NOT NULL AND p_roli = 'bemor' THEN
    SELECT k.xona_id INTO v_xona FROM koykalar k WHERE k.id = p_koyka;
    v_xona_summa := xona_narxi(v_xona);
  END IF;

  INSERT INTO yotqizishlar (bemor_id, koyka_id, roli, asosiy_id,
                            kirish_sana, reja_chiqish, summa, xona_summa)
  VALUES (v_bemor, p_koyka, p_roli, p_asosiy,
          p_kirish, p_reja_chiqish, v_summa, v_xona_summa)
  RETURNING id INTO v_yotqizish;

  IF p_oldindan > 0 THEN
    PERFORM huquq_tekshir(
      ARRAY['super_admin','buxgalter','administrator']::rol_turi[],
      'oldindan to''lovni kiritish');
    INSERT INTO tolovlar (yotqizish_id, summa, sana, izoh, kim)
    VALUES (v_yotqizish, p_oldindan, p_kirish, 'Oldindan to''lov', joriy_fish());
  END IF;

  RETURN v_yotqizish;
END $$;

-- Keyin joylashtirilgan bemorga ham xona puli yoziladi
CREATE OR REPLACE FUNCTION koyka_biriktir(p_yotqizish int, p_koyka int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_xona int; v_roli shaxs_roli; v_holat yotqizish_holati;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'xonaga joylashtirish');

  SELECT roli, holat INTO v_roli, v_holat FROM yotqizishlar WHERE id = p_yotqizish;
  IF v_holat IS DISTINCT FROM 'yotmoqda' THEN
    RAISE EXCEPTION 'Yotqizish topilmadi yoki bemor chiqib ketgan.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE yotqizishlar SET koyka_id = p_koyka WHERE id = p_yotqizish;

  IF p_koyka IS NOT NULL AND v_roli = 'bemor' THEN
    SELECT k.xona_id INTO v_xona FROM koykalar k WHERE k.id = p_koyka;
    UPDATE yotqizishlar SET xona_summa = xona_narxi(v_xona)
     WHERE id = p_yotqizish;
  END IF;
END $$;

-- xona_yarat: narx endi turdan olinadi, parametri saqlanadi (eski chaqiruvlar buzilmasin)
CREATE OR REPLACE FUNCTION xona_yarat(
  p_bolim text, p_raqam text, p_turi text, p_sigim int, p_narx numeric DEFAULT NULL
) RETURNS integer LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_xona integer; v_bolim smallint;
BEGIN
  SELECT id INTO v_bolim FROM bolimlar WHERE nomi = p_bolim;
  IF v_bolim IS NULL THEN
    RAISE EXCEPTION 'Boʻlim topilmadi: %', p_bolim;
  END IF;

  INSERT INTO xona_turlari (nomi, narx)
  VALUES (p_turi, COALESCE(p_narx, 0)) ON CONFLICT (nomi) DO NOTHING;

  INSERT INTO xonalar (bolim_id, raqam, turi, narx)
  VALUES (v_bolim, p_raqam, p_turi,
          (SELECT narx FROM xona_turlari WHERE nomi = p_turi))
  RETURNING id INTO v_xona;

  INSERT INTO koykalar (xona_id, raqam)
  SELECT v_xona, g FROM generate_series(1, p_sigim) g;
  RETURN v_xona;
END $$;

-- ------------------------------------------------------------
-- 4. SOZLAMALAR UCHUN KO'RINISH — turlar va ularning xonalari
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_xona_narxlari;
CREATE VIEW v_xona_narxlari
WITH (security_invoker = on) AS
SELECT t.nomi                AS turi,
       t.narx,
       t.tartib,
       count(DISTINCT x.id)  AS xona_soni,
       count(k.id)           AS koyka_soni,
       string_agg(DISTINCT x.raqam, ', ' ORDER BY x.raqam) AS xonalar
FROM xona_turlari t
  LEFT JOIN xonalar x  ON x.turi = t.nomi
  LEFT JOIN koykalar k ON k.xona_id = x.id
GROUP BY t.nomi, t.narx, t.tartib
ORDER BY t.tartib, t.nomi;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

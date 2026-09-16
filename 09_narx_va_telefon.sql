-- ============================================================
--  09_narx_va_telefon.sql
--  01, 03, 05, 06, 08 dan KEYIN ishga tushiriladi. Idempotent.
--
--  Mijoz qarorlari boʻyicha uchta oʻzgarish:
--   1. Telefon raqami takrorlanmaydi (asosiy bemorlar uchun).
--      Farzand va qarovchi ota-onasining raqamidan foydalanaveradi.
--   2. Barcha narxlar Sozlamalardan oʻzgartiriladi —
--      super_admin va buxgalter. Har bir oʻzgarish yozib boriladi.
--   3. Qarz bilan chiqarish BEKOR QILINDI.
--      Amaldagi tartib: buxgalter chek beradi -> qorovul chekni
--      koʻrib chiqaradi. Ya'ni qarzli bemor baribir chiqa olmaydi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
--   Fayllar tartib bilan ishga tushirilishi kerak. Biror
--   oldingisi qolib ketgan bo'lsa, tushunarli xabar beramiz.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.v_tasdiqlanmagan') IS NULL THEN
    RAISE EXCEPTION 'Avval 06_tuzatishlar.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'bemor_qabul') THEN
    RAISE EXCEPTION 'Avval 08_hamrohlar.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. TELEFON RAQAMI TAKRORLANMASIN
--    Raqam turli koʻrinishda yozilishi mumkin ("+998 90 123 45 67"
--    va "998901234567"), shuning uchun taqqoslash faqat raqamlar
--    boʻyicha boradi.
-- ------------------------------------------------------------
ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS hamroh boolean NOT NULL DEFAULT false;

ALTER TABLE bemorlar ADD COLUMN IF NOT EXISTS telefon_raqam text
  GENERATED ALWAYS AS (regexp_replace(COALESCE(telefon,''), '\D', '', 'g')) STORED;

-- Bu fayldan OLDIN kiritilgan farzand va qarovchilarda "hamroh" belgisi
-- yo'q edi — ular ham asosiy bemor deb hisoblanardi va ota-onasining
-- raqami takror bo'lib ko'rinardi. Avval o'shalarni belgilaymiz.
UPDATE bemorlar b SET hamroh = true
WHERE NOT b.hamroh
  AND EXISTS (SELECT 1 FROM yotqizishlar y
               WHERE y.bemor_id = b.id AND y.roli <> 'bemor')
  AND NOT EXISTS (SELECT 1 FROM yotqizishlar y
                   WHERE y.bemor_id = b.id AND y.roli = 'bemor');

-- Shundan keyin ham haqiqiy takror qolsa — indeks yaratib bo'lmaydi.
-- Kimligini aniq aytamiz, qo'lda tuzatiladi.
DO $$
DECLARE v text;
BEGIN
  SELECT string_agg(satr, E'\n  ') INTO v FROM (
    SELECT b.telefon_raqam || '  ->  #' || b.id || ' ' ||
           b.familiya || ' ' || b.ism AS satr
    FROM bemorlar b
    WHERE NOT b.hamroh AND b.telefon_raqam <> ''
      AND b.telefon_raqam IN (
        SELECT telefon_raqam FROM bemorlar
        WHERE NOT hamroh AND telefon_raqam <> ''
        GROUP BY telefon_raqam HAVING count(*) > 1)
    ORDER BY b.telefon_raqam, b.id
  ) q;
  IF v IS NOT NULL THEN
    RAISE EXCEPTION E'Bir xil telefon raqamli asosiy bemorlar bor. Ularni tuzating yoki biri hamroh (farzand/qarovchi) boʻlsa shunday belgilang:\n  %', v;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS bemorlar_telefon_uniq
  ON bemorlar (telefon_raqam)
  WHERE NOT hamroh AND telefon_raqam <> '';

-- bemor_joylashtir: hamrohni belgilaymiz va takrorni oldindan ushlaymiz
--
-- DIQQAT: 11_xona_turlari.sql bu funksiyani yana bir marta qayta yozadi
-- (xona narxi xona TURIdan olinadi). 11 ishga tushgan bazada bu yerdagi
-- variant uni bosib ketmasligi kerak.
DO $blokj$
BEGIN
IF to_regclass('public.xona_turlari') IS NOT NULL THEN
  RAISE NOTICE '11_xona_turlari.sql ishga tushgan — bemor_joylashtir() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
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
  v_xona int; v_band int; v_mavjud int; v_raqam text;
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

    -- asosiy bemor uchun raqam takrorlanmasligi kerak
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
            p_roli <> 'bemor')          -- farzand va qarovchi -> hamroh
    RETURNING id INTO v_bemor;
  END IF;

  v_summa := narx_hisobla(p_yosh, p_chet_el, p_roli);

  IF p_koyka IS NOT NULL THEN
    SELECT k.xona_id INTO v_xona FROM koykalar k WHERE k.id = p_koyka;
    SELECT count(*) INTO v_band
    FROM yotqizishlar y JOIN koykalar k2 ON k2.id = y.koyka_id
    WHERE k2.xona_id = v_xona AND y.holat = 'yotmoqda';
    IF v_band = 0 AND p_roli = 'bemor' THEN
      SELECT narx INTO v_xona_summa FROM xonalar WHERE id = v_xona;
    END IF;
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
END $$
$f$;
END $blokj$;

-- ------------------------------------------------------------
-- 2. NARXLARNI SOZLAMALARDAN BOSHQARISH
--    super_admin va buxgalter. Har bir oʻzgarish yozib boriladi —
--    pulga tegadigan sozlama izsiz oʻzgarmasligi kerak.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS narx_tarixi (
  id       serial PRIMARY KEY,
  tur      text NOT NULL,                -- 'tarif' yoki 'xona'
  nomi     text NOT NULL,                -- tarif kaliti yoki xona raqami
  eski     numeric(12,0),
  yangi    numeric(12,0) NOT NULL,
  kim      text,
  vaqt     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE narx_tarixi ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS korish ON narx_tarixi;
CREATE POLICY korish ON narx_tarixi FOR SELECT USING (joriy_rol() IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_narx_tarixi_vaqt ON narx_tarixi (vaqt DESC);

DO $bt$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname='buxgalter_toraytirildi') THEN
  RAISE NOTICE '18_buxgalter.sql ishga tushgan — tarif_ozgartir() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION tarif_ozgartir(p_kalit text, p_qiymat numeric, p_izoh text DEFAULT NULL)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_eski numeric;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','buxgalter']::rol_turi[], 'narxni oʻzgartirish');
  IF p_qiymat IS NULL OR p_qiymat < 0 THEN
    RAISE EXCEPTION 'Narx manfiy boʻlishi mumkin emas.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT qiymat INTO v_eski FROM tariflar WHERE kalit = p_kalit;

  IF v_eski IS NULL THEN
    INSERT INTO tariflar (kalit, qiymat, izoh) VALUES (p_kalit, p_qiymat, p_izoh);
  ELSE
    UPDATE tariflar SET qiymat = p_qiymat,
                        izoh = COALESCE(p_izoh, izoh)
     WHERE kalit = p_kalit;
  END IF;

  INSERT INTO narx_tarixi (tur, nomi, eski, yangi, kim)
  VALUES ('tarif', p_kalit, v_eski, p_qiymat, joriy_fish());
  RETURN p_qiymat;
END $$
$f$;
END $bt$;


DO $bx$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname='buxgalter_toraytirildi') THEN
  RAISE NOTICE '18_buxgalter.sql ishga tushgan — xona_narx_ozgartir() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION xona_narx_ozgartir(p_xona int, p_narx numeric)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_eski numeric; v_raqam text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','buxgalter']::rol_turi[], 'xona narxini oʻzgartirish');
  IF p_narx IS NULL OR p_narx < 0 THEN
    RAISE EXCEPTION 'Narx manfiy boʻlishi mumkin emas.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT narx, raqam INTO v_eski, v_raqam FROM xonalar WHERE id = p_xona;
  IF v_raqam IS NULL THEN
    RAISE EXCEPTION 'Xona topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE xonalar SET narx = p_narx WHERE id = p_xona;
  INSERT INTO narx_tarixi (tur, nomi, eski, yangi, kim)
  VALUES ('xona', v_raqam || '-xona', v_eski, p_narx, joriy_fish());
  RETURN p_narx;
END $$
$f$;
END $bx$;


-- Sigʻimi bir xil boʻlgan barcha xonalarga bir narx (3 va 4 kishilik
-- xonalar narxini bir marta belgilash uchun)
DO $bs$
BEGIN
IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public' AND p.proname='buxgalter_toraytirildi') THEN
  RAISE NOTICE '18_buxgalter.sql ishga tushgan — xona_narx_sigim() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION xona_narx_sigim(p_sigim int, p_narx numeric)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE r record; v_soni int := 0;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','buxgalter']::rol_turi[], 'xona narxini oʻzgartirish');
  IF p_narx IS NULL OR p_narx < 0 THEN
    RAISE EXCEPTION 'Narx manfiy boʻlishi mumkin emas.' USING ERRCODE = 'check_violation';
  END IF;

  FOR r IN
    SELECT x.id, x.raqam, x.narx
    FROM xonalar x
    WHERE (SELECT count(*) FROM koykalar k WHERE k.xona_id = x.id) = p_sigim
  LOOP
    UPDATE xonalar SET narx = p_narx WHERE id = r.id;
    INSERT INTO narx_tarixi (tur, nomi, eski, yangi, kim)
    VALUES ('xona', r.raqam || '-xona', r.narx, p_narx, joriy_fish());
    v_soni := v_soni + 1;
  END LOOP;
  RETURN v_soni;
END $$
$f$;
END $bs$;


-- Sozlamalar ekrani uchun: xonalar sigʻimi va narxi
-- 11_xona_turlari.sql bu ko'rinishni xona TURI bo'yicha qayta
-- yozadi. U allaqachon ishga tushgan bo'lsa, eski (har bir xona
-- bo'yicha) variantni tiklab, Sozlamalar ekranini buzmaymiz.
DO $blokn$
BEGIN
IF to_regclass('public.xona_turlari') IS NOT NULL THEN
  RAISE NOTICE '11_xona_turlari.sql ishga tushgan — v_xona_narxlari o''zgartirilmaydi.';
  RETURN;
END IF;
DROP VIEW IF EXISTS v_xona_narxlari;
EXECUTE $v$
CREATE VIEW v_xona_narxlari
WITH (security_invoker = on) AS
SELECT x.id AS xona_id, x.raqam AS xona, bo.nomi AS bolim, bo.id AS bolim_id,
       x.turi, x.narx, x.tamirlashda,
       count(k.id) AS sigim
FROM xonalar x
  JOIN bolimlar bo ON bo.id = x.bolim_id
  LEFT JOIN koykalar k ON k.xona_id = x.id
GROUP BY x.id, x.raqam, bo.nomi, bo.id, x.turi, x.narx, x.tamirlashda
ORDER BY bo.tartib, x.raqam
$v$;
END $blokn$;

-- ------------------------------------------------------------
-- 3. QARZ BILAN CHIQARISH — BEKOR QILINDI
--    Qarzi bor bemor hech qanday yoʻl bilan chiqarilmaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bemor_chiqar_qarz_bilan(int, text, timestamptz);

-- 10_kunlik_hisob.sql bu triggerga kunlik hisobni qo'shadi.
-- U ishga tushgan bo'lsa, eski variantni tiklamaymiz.
DO $blokt$
BEGIN
IF EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='v_yotqizishlar'
              AND column_name='kurs_summa') THEN
  RAISE NOTICE '10_kunlik_hisob.sql ishga tushgan — trg_qarz_tekshir() o''zgartirilmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION trg_qarz_tekshir() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_qarz numeric;
BEGIN
  IF NEW.haqiqiy_chiqish IS NOT NULL AND OLD.haqiqiy_chiqish IS NULL THEN
    SELECT GREATEST(0, NEW.summa + NEW.xona_summa - tolangan(NEW.id)) INTO v_qarz;
    IF v_qarz > 0 THEN
      RAISE EXCEPTION 'Bemorni chiqarish mumkin emas. Toʻlanmagan qarzdorlik: % soʻm. Avval buxgalterdan chek olinadi.',
        to_char(v_qarz, 'FM999G999G999')
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.holat := 'chiqdi';
  END IF;
  RETURN NEW;
END $$
$f$;
END $blokt$;

-- anon yopiq qolsin
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 4. Qidiruv natijasida hamrohlar ajratilsin
--    (takror raqam ogohlantirishi faqat asosiy bemorlarga tegishli)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bemor_qidir(text);
CREATE FUNCTION bemor_qidir(p_matn text)
RETURNS TABLE (id int, fish text, telefon text, jins jins_turi,
               yosh int, hamroh boolean, oxirgi_tashrif date)
LANGUAGE sql STABLE AS $$
  SELECT b.id, b.familiya || ' ' || b.ism, b.telefon, b.jins,
         bemor_yoshi(b), b.hamroh, max(y.kirish_sana)
  FROM bemorlar b LEFT JOIN yotqizishlar y ON y.bemor_id = b.id
  WHERE b.telefon_raqam = regexp_replace(COALESCE(p_matn,''), '\D', '', 'g')
     OR (b.familiya || ' ' || b.ism) ILIKE '%' || p_matn || '%'
  GROUP BY b.id
  ORDER BY b.hamroh, max(y.kirish_sana) DESC NULLS LAST
  LIMIT 20;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

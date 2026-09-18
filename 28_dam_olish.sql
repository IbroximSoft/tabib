-- ============================================================
--  28_dam_olish.sql — DAVOLANISH / DAM OLISH BOSQICHLARI
--  01..27 dan KEYIN. Idempotent.
--
--  MUAMMO
--    Bemor davolanishni to'xtatib, xuddi shu xonada shunchaki
--    DAM OLISHI mumkin (ovqat kiradi, davolanish kirmaydi) —
--    narxi xona turiga (Standart/Premium...) qarab boshqacha,
--    KUNLIK. Keyin xohlagan kuni yana davolanishni — bu safar
--    YANGI KURS sifatida — davom ettirishi mumkin. Hammasi bitta
--    xonada, bemor hech qayerga chiqib ketmasdan.
--
--  MIJOZ QARORLARI (suhbatda tasdiqlangan)
--   1. Dam olish narxi — KUNLIK stavka (necha kun dam olsa,
--      shuncha kun uchun to'laydi, "to'liq kurs" tushunchasi yo'q).
--   2. Davolanishdan dam olishga (yoki aksincha) o'tganda, ORQADA
--      QOLGAN BOSQICH SHU ZAHOTI MUZLAYDI VA TO'LANGAN BO'LISHI
--      SHART — xuddi bemorni chiqarishda bo'lgani kabi, qarz
--      turib bosqich almashtirib bo'lmaydi. Masalan: 3 kun
--      davolangan bemor dam olishga chiqsa — avval o'sha 3
--      kunlik davolanish puli to'lanadi, SO'NG dam olish bosqichi
--      boshlanadi.
--   3. Qarovchi/farzand narxi bemorning davolanish/dam olish
--      holatidan ta'sirlanmaydi — ular o'zgarishsiz qoladi.
--
--  YECHIM
--    yotqizishlar ga 4 ta YANGI ustun (eskilariga tegilmaydi):
--      holat_turi      — hozirgi bosqich: 'davolanish' | 'dam_olish'
--      davr_boshi      — hozirgi bosqich qachon boshlangani
--                        (boshida kirish_sana bilan bir xil)
--      avvalgi_summa   — tugagan (muzlagan) bosqichlardan yig'ilgan
--      dam_kunlik_narx — dam olish bosqichi uchun, o'sha payt
--                        xona turidan olingan KUNLIK narx (muzlab
--                        qoladi — keyinchalik narx o'zgarsa ham
--                        bu bosqichga ta'sir qilmaydi)
--
--    davr_hisob() — bitta umumiy formula (SQL, yon ta'sirsiz):
--    berilgan bosqich turi/kunlar/narxlar bo'yicha SHU BOSQICHNING
--    hozirgacha necha so'mligini hisoblaydi. hisob() ham,
--    chiqarishdagi trg_qarz_tekshir() ham, holat_ozgartir() ham —
--    UCHALASI ANA SHU BITTA FORMULADAN foydalanadi. Shu tufayli
--    "hisob() bilan chiqarish bir xil hisoblashi kerak" degan
--    eski muammo endi BUTUNLAY yo'qoladi — ular endi bitta
--    manbadan o'qiydi, ikki joyda qo'lda takrorlanmaydi.
--
--    holat_ozgartir(p_yotqizish, p_yangi_holat):
--      1. Joriy bosqichni BUGUNGACHA hisoblaydi (davr_hisob orqali).
--      2. Qarz bo'lsa — XATOLIK beradi, o'tkazmaydi (2-band).
--      3. Qarz yo'q bo'lsa: hisoblangan summani avvalgi_summaga
--         qo'shadi (muzlatadi), yangi bosqichni boshlaydi
--         (davr_boshi=bugun, holat_turi=yangi, mos narx yoziladi).
--
--    xona puli (xona_summa) — ESKICHA, faqat BIRINCHI bosqichda
--    ishtirok etadi (proratsiyalanadi). 2-bosqichdan boshlab har
--    doim 0 — xona puli qayta olinmaydi (bitta xona uchun bir marta).
--
--    Bemor -> Qarovchi (bemorni_qarovchiga) — 08_hamrohlar.sql dagi
--    qarovchi->bemor ('qarovchini_bemorga') ning TESKARI yo'nalishi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='bemor_malumotlari_ornatildi') THEN
    RAISE EXCEPTION 'Avval 27_bemor_malumotlari.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. DAM OLISH NARXI — xona turiga bog'liq, kunlik
-- ------------------------------------------------------------
ALTER TABLE xona_turlari ADD COLUMN IF NOT EXISTS dam_olish_narxi numeric(12,0) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION xona_turi_dam_narx(p_turi text, p_narx numeric)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_eski numeric;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[],
                        'dam olish narxini oʻzgartirish');

  IF p_narx IS NULL OR p_narx < 0 THEN
    RAISE EXCEPTION 'Narx manfiy boʻlishi mumkin emas.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT dam_olish_narxi INTO v_eski FROM xona_turlari WHERE nomi = p_turi;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Xona turi topilmadi: %', p_turi USING ERRCODE = 'check_violation';
  END IF;

  UPDATE xona_turlari SET dam_olish_narxi = p_narx WHERE nomi = p_turi;

  INSERT INTO narx_tarixi (tur, nomi, eski, yangi, kim)
  VALUES ('dam_olish_narxi', p_turi, v_eski, p_narx, joriy_fish());

  RETURN p_narx;
END $$;

-- ------------------------------------------------------------
-- 2. YOTQIZISHLARGA YANGI USTUNLAR
-- ------------------------------------------------------------
ALTER TABLE yotqizishlar ADD COLUMN IF NOT EXISTS holat_turi text;
ALTER TABLE yotqizishlar ADD COLUMN IF NOT EXISTS davr_boshi date;
ALTER TABLE yotqizishlar ADD COLUMN IF NOT EXISTS avvalgi_summa numeric(12,0);
ALTER TABLE yotqizishlar ADD COLUMN IF NOT EXISTS dam_kunlik_narx numeric(12,0);

UPDATE yotqizishlar SET holat_turi = 'davolanish' WHERE holat_turi IS NULL;
UPDATE yotqizishlar SET davr_boshi = kirish_sana WHERE davr_boshi IS NULL;
UPDATE yotqizishlar SET avvalgi_summa = 0 WHERE avvalgi_summa IS NULL;

ALTER TABLE yotqizishlar ALTER COLUMN holat_turi SET NOT NULL;
ALTER TABLE yotqizishlar ALTER COLUMN holat_turi SET DEFAULT 'davolanish';
ALTER TABLE yotqizishlar ALTER COLUMN davr_boshi SET NOT NULL;
ALTER TABLE yotqizishlar ALTER COLUMN davr_boshi SET DEFAULT current_date;
ALTER TABLE yotqizishlar ALTER COLUMN avvalgi_summa SET NOT NULL;
ALTER TABLE yotqizishlar ALTER COLUMN avvalgi_summa SET DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'yotqizishlar_holat_turi_ck') THEN
    ALTER TABLE yotqizishlar ADD CONSTRAINT yotqizishlar_holat_turi_ck
      CHECK (holat_turi IN ('davolanish','dam_olish'));
  END IF;
END $$;

-- ------------------------------------------------------------
-- 3. BITTA UMUMIY HISOB FORMULASI
--    p_kun — chaqiruvchi tomonidan tayyorlab beriladi (hisob()da
--    "hali yotibdi" uchun GREATEST(0,...), chiqarishda "chiqqan
--    kuni ham 1 kun" uchun GREATEST(1,...) — eski xatti-harakat
--    saqlanadi).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION davr_hisob(
  p_holat_turi text, p_kun int,
  p_summa numeric, p_xona_summa numeric, p_dam_kunlik numeric,
  p_kurs_kun numeric
) RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_holat_turi = 'dam_olish' THEN
      round(COALESCE(p_dam_kunlik, 0) * GREATEST(p_kun, 0))
    WHEN p_kurs_kun IS NULL OR p_kurs_kun <= 0 OR p_kun >= p_kurs_kun THEN
      COALESCE(p_summa, 0) + COALESCE(p_xona_summa, 0)
    ELSE
      round((COALESCE(p_summa, 0) + COALESCE(p_xona_summa, 0))
            * GREATEST(p_kun, 0) / p_kurs_kun)
  END
$$;

-- ------------------------------------------------------------
-- 4. HISOB() — endi avvalgi (muzlagan) bosqichlar + joriy bosqich
--    Eski bitta-kursli bemorda NATIJA BIR XIL qoladi: holat_turi
--    default 'davolanish', davr_boshi=kirish_sana, avvalgi_summa=0
--    bo'lgani uchun davr_hisob() aynan eski formulani beradi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION hisob(p_yotqizish int) RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE
  y record; v_kurs numeric; v_kun int;
BEGIN
  SELECT koyka_id, haqiqiy_chiqish, summa, xona_summa,
         holat_turi, davr_boshi, avvalgi_summa, dam_kunlik_narx
    INTO y FROM yotqizishlar WHERE id = p_yotqizish;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- xonaga joylashtirilmagan bemordan pul olinmaydi
  IF y.koyka_id IS NULL THEN RETURN 0; END IF;

  -- chiqarilgan bemorda summa allaqachon yakuniy holatda saqlangan
  IF y.haqiqiy_chiqish IS NOT NULL THEN
    RETURN COALESCE(y.summa, 0) + COALESCE(y.xona_summa, 0);
  END IF;

  SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
  v_kun := GREATEST(0, current_date - y.davr_boshi + 1);

  RETURN COALESCE(y.avvalgi_summa, 0)
       + davr_hisob(y.holat_turi, v_kun, y.summa, y.xona_summa, y.dam_kunlik_narx, v_kurs);
END $$;

-- qarz() o'zgarmaydi — u allaqachon hisob() orqali ishlaydi (10_kunlik_hisob.sql)

-- ------------------------------------------------------------
-- 5. CHIQARISHDA MUZLATISH — bir xil davr_hisob() dan foydalanadi
--    24_qaytarish.sql dagi "ortiqcha to'lov" tekshiruvi SAQLANADI,
--    faqat summa/xona_summa hisoblash usuli yangilanadi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_qarz_tekshir() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_qarz numeric; v_kurs numeric; v_kun int; v_joriy numeric; v_ortiqcha numeric;
BEGIN
  IF NEW.haqiqiy_chiqish IS NOT NULL AND OLD.haqiqiy_chiqish IS NULL THEN

    IF NEW.koyka_id IS NULL THEN
      -- xonasiz yozuv: pul hisoblanmaydi
      NEW.summa := 0;
      NEW.xona_summa := 0;
    ELSE
      SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
      v_kun := GREATEST(1,
        (NEW.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date - NEW.davr_boshi + 1);

      v_joriy := davr_hisob(NEW.holat_turi, v_kun, NEW.summa, NEW.xona_summa,
                            NEW.dam_kunlik_narx, v_kurs);

      IF NEW.holat_turi = 'dam_olish' THEN
        NEW.xona_summa := 0;
      ELSIF v_kurs IS NOT NULL AND v_kurs > 0 AND v_kun < v_kurs THEN
        -- eski aniq formula: xona puli ham xuddi shu nisbatda kamayadi
        NEW.xona_summa := round(COALESCE(NEW.xona_summa, 0) * v_kun::numeric / v_kurs);
      END IF;

      NEW.summa := COALESCE(NEW.avvalgi_summa, 0) + v_joriy - COALESCE(NEW.xona_summa, 0);

      NEW.izoh := COALESCE(NEW.izoh || ' | ', '') ||
        format('Bosqich hisobi: %s kun (%s), shu bosqich: %s soʻm',
               v_kun, NEW.holat_turi, pul_matn(v_joriy));
    END IF;

    v_qarz := GREATEST(0, NEW.summa + NEW.xona_summa - tolangan(NEW.id));
    IF v_qarz > 0 THEN
      RAISE EXCEPTION 'Bemorni chiqarish mumkin emas. Toʻlanmagan qarzdorlik: % soʻm. Avval buxgalterdan chek olinadi.',
        pul_matn(v_qarz)
        USING ERRCODE = 'check_violation';
    END IF;

    -- teskari holat — bemor hisobdan ortiq toʻlagan (24_qaytarish.sql)
    v_ortiqcha := GREATEST(0, tolangan(NEW.id) - (NEW.summa + NEW.xona_summa));
    IF v_ortiqcha > 0
       AND COALESCE(current_setting('app.ortiqcha_ruxsat', true), '') <> 'ha' THEN
      RAISE EXCEPTION 'Bemorni chiqarish mumkin emas. Bemorga % soʻm qaytarilishi kerak — erta ketgani uchun hisob kamaydi. “Chiqarish va pulni qaytarish” orqali rasmiylashtiring.',
        pul_matn(v_ortiqcha)
        USING ERRCODE = 'check_violation';
    END IF;

    NEW.holat := 'chiqdi';
  END IF;
  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 6. HOLATNI ALMASHTIRISH — davolanish <-> dam olish
--    Kim: super_admin, administrator, buxgalter (kassir shu
--    rollarda ishlaydi — tolov_qosh() bilan bir xil ro'yxat).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION holat_ozgartir(p_yotqizish int, p_yangi_holat text)
RETURNS TABLE (
  yakunlangan_kun   int,
  yakunlangan_summa numeric,
  yangi_holat       text,
  yangi_summa       numeric
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  y yotqizishlar%ROWTYPE;
  v_kurs numeric; v_kun int; v_joriy numeric; v_qarz numeric;
  v_yangi_summa numeric := 0; v_yangi_dam_kunlik numeric;
  v_yosh int; v_chet boolean;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator','buxgalter']::rol_turi[],
                        'davolanish/dam olish holatini oʻzgartirish');

  IF p_yangi_holat NOT IN ('davolanish','dam_olish') THEN
    RAISE EXCEPTION 'Holat notoʻgʻri: %', p_yangi_holat USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO y FROM yotqizishlar WHERE id = p_yotqizish FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;
  IF y.holat <> 'yotmoqda' THEN
    RAISE EXCEPTION 'Bemor allaqachon chiqarilgan yoki bekor qilingan.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF y.roli <> 'bemor' THEN
    RAISE EXCEPTION 'Bu amal faqat asosiy bemorga qoʻllanadi (hamroh/qarovchiga emas).'
      USING ERRCODE = 'check_violation';
  END IF;
  IF y.koyka_id IS NULL THEN
    RAISE EXCEPTION 'Xonasiz yozuvda holatni oʻzgartirib boʻlmaydi.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF y.holat_turi = p_yangi_holat THEN
    RAISE EXCEPTION 'Bemor allaqachon shu holatda.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
  v_kun := GREATEST(1, current_date - y.davr_boshi + 1);
  v_joriy := davr_hisob(y.holat_turi, v_kun, y.summa, y.xona_summa, y.dam_kunlik_narx, v_kurs);

  -- ⭐ ASOSIY QOIDA: qarz turib holat almashtirilmaydi.
  v_qarz := GREATEST(0, COALESCE(y.avvalgi_summa, 0) + v_joriy - tolangan(p_yotqizish));
  IF v_qarz > 0 THEN
    RAISE EXCEPTION 'Holatni oʻzgartirib boʻlmaydi. Joriy bosqich (%s, %s kun) uchun toʻlanmagan qarz bor: % soʻm. Avval toʻlovni qabul qiling.',
      y.holat_turi, v_kun, pul_matn(v_qarz)
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_yangi_holat = 'davolanish' THEN
    SELECT bemor_yoshi(b), b.chet_el INTO v_yosh, v_chet
    FROM bemorlar b WHERE b.id = y.bemor_id;
    v_yangi_summa := narx_hisobla(v_yosh, v_chet, 'bemor'::shaxs_roli);
    v_yangi_dam_kunlik := NULL;
  ELSE
    SELECT t.dam_olish_narxi INTO v_yangi_dam_kunlik
    FROM koykalar k JOIN xonalar x ON x.id = k.xona_id JOIN xona_turlari t ON t.nomi = x.turi
    WHERE k.id = y.koyka_id;
    v_yangi_summa := 0;
  END IF;

  UPDATE yotqizishlar SET
    avvalgi_summa   = COALESCE(y.avvalgi_summa, 0) + v_joriy,
    holat_turi      = p_yangi_holat,
    davr_boshi      = current_date,
    summa           = v_yangi_summa,
    xona_summa      = 0,
    dam_kunlik_narx = v_yangi_dam_kunlik,
    izoh = COALESCE(izoh || ' | ', '') ||
      format('%s (%s kun) yakunlandi — %s soʻm. Endi: %s. Kim: %s',
             y.holat_turi, v_kun, pul_matn(v_joriy), p_yangi_holat, joriy_fish())
  WHERE id = p_yotqizish;

  RETURN QUERY SELECT v_kun, v_joriy, p_yangi_holat, v_yangi_summa;
END $$;

-- ------------------------------------------------------------
-- 7. BEMOR -> QAROVCHI (08_hamrohlar.sql dagi teskarisi)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bemorni_qarovchiga(p_yotqizish int)
RETURNS TABLE (
  bemor_kuni    int,
  bemor_puli    numeric,
  qarovchi_puli numeric
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  y yotqizishlar%ROWTYPE;
  v_kurs numeric; v_kun int; v_joriy numeric; v_qarz numeric; v_qarovchi numeric;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bemorni qarovchiga aylantirish');

  SELECT * INTO y FROM yotqizishlar
   WHERE id = p_yotqizish AND roli = 'bemor' AND holat = 'yotmoqda'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bu yozuv asosiy bemor emas yoki allaqachon chiqarilgan.'
      USING ERRCODE = 'check_violation';
  END IF;
  IF y.koyka_id IS NULL THEN
    RAISE EXCEPTION 'Xonasiz yozuvda bu amal ishlamaydi.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM yotqizishlar h
              WHERE h.asosiy_id = p_yotqizish AND h.holat = 'yotmoqda') THEN
    RAISE EXCEPTION 'Bu bemorga biriktirilgan hamrohlar bor — avval ularni chiqaring yoki boshqa asosiy bemorga oʻtkazing.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
  v_kun := GREATEST(1, current_date - y.davr_boshi + 1);
  v_joriy := davr_hisob(y.holat_turi, v_kun, y.summa, y.xona_summa, y.dam_kunlik_narx, v_kurs);

  v_qarz := GREATEST(0, COALESCE(y.avvalgi_summa, 0) + v_joriy - tolangan(p_yotqizish));
  IF v_qarz > 0 THEN
    RAISE EXCEPTION 'Bemorni qarovchiga aylantirib boʻlmaydi. Joriy bosqich uchun toʻlanmagan qarz bor: % soʻm.',
      pul_matn(v_qarz)
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT qiymat INTO v_qarovchi FROM tariflar WHERE kalit = 'qarovchi';

  UPDATE yotqizishlar SET
    roli            = 'qarovchi',
    avvalgi_summa   = COALESCE(y.avvalgi_summa, 0) + v_joriy,
    holat_turi      = 'davolanish',
    davr_boshi      = current_date,
    summa           = v_qarovchi,
    xona_summa      = 0,
    dam_kunlik_narx = NULL,
    izoh = COALESCE(izoh || ' | ', '') ||
      format('Bemor → Qarovchi (%s kun, %s soʻm hisoblandi). Kim: %s',
             v_kun, pul_matn(v_joriy), joriy_fish())
  WHERE id = p_yotqizish;

  RETURN QUERY SELECT v_kun, v_joriy, v_qarovchi;
END $$;

-- ------------------------------------------------------------
-- 8. KO'RINISHLAR — yangi ustunlar qo'shiladi
--    27_bemor_malumotlari.sql dagi variantni SUPERSEDE qiladi.
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_yotqizishlar;
CREATE VIEW v_yotqizishlar
WITH (security_invoker = on) AS
SELECT
  y.id AS yotqizish_id, b.id AS bemor_id,
  b.familiya, b.ism, b.familiya || ' ' || b.ism AS fish,
  b.otasining_ismi, b.tugilgan_sana,
  b.viloyat, b.tuman, b.mahalla, b.kocha, b.uy_raqami, b.kvartira,
  b.jins, b.telefon, b.chet_el, b.fuqaroligi,
  bemor_yoshi(b) AS yosh,
  y.roli, y.holat,
  CASE y.holat WHEN 'yotmoqda' THEN 'Yotmoqda' WHEN 'chiqdi' THEN 'Chiqdi'
               ELSE 'Bekor qilingan' END AS holat_matn,
  y.holat_turi,
  CASE y.holat_turi WHEN 'dam_olish' THEN 'Dam olmoqda' ELSE 'Davolanmoqda' END AS holat_turi_matn,
  y.davr_boshi, y.avvalgi_summa, y.dam_kunlik_narx,
  bo.id AS bolim_id, bo.nomi AS bolim,
  x.id AS xona_id, x.raqam AS xona, x.turi AS xona_turi, k.raqam AS koyka,
  (y.koyka_id IS NOT NULL) AS xonada,
  y.kirish_sana, y.kirish_vaqt, y.reja_chiqish,
  (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date AS haqiqiy_chiqish,
  y.haqiqiy_chiqish AS haqiqiy_chiqish_vaqt,
  (COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, current_date)
     - y.kirish_sana + 1) AS yotgan_kun,
  CASE WHEN y.haqiqiy_chiqish IS NOT NULL
       THEN (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date - y.reja_chiqish
  END AS reja_farqi,
  y.summa AS bemor_summa,
  y.xona_summa,
  y.avvalgi_summa + y.summa + y.xona_summa AS kurs_summa,  -- jami nominal (hozirgacha)
  hisob(y.id)            AS umumiy,          -- hozirgi haqiqiy hisob
  tolangan(y.id)         AS tolangan,
  qarz(y.id)             AS qarz,
  (qarz(y.id) > 0)       AS qarzdor,
  y.band_davri, y.izoh,
  y.asosiy_id,
  ab.familiya || ' ' || ab.ism AS asosiy_fish,
  (SELECT count(*) FROM yotqizishlar h
    WHERE h.asosiy_id = y.id AND h.holat <> 'bekor') AS hamroh_soni,
  y.tashxis
FROM yotqizishlar y
  JOIN bemorlar b        ON b.id = y.bemor_id
  LEFT JOIN koykalar k   ON k.id = y.koyka_id
  LEFT JOIN xonalar x    ON x.id = k.xona_id
  LEFT JOIN bolimlar bo  ON bo.id = x.bolim_id
  LEFT JOIN yotqizishlar ay ON ay.id = y.asosiy_id
  LEFT JOIN bemorlar ab  ON ab.id = ay.bemor_id;

DROP VIEW IF EXISTS v_hozir_yotganlar CASCADE;
CREATE VIEW v_hozir_yotganlar
WITH (security_invoker = on) AS
SELECT y.id AS yotqizish_id, b.id AS bemor_id,
       b.familiya || ' ' || b.ism AS fish,
       b.jins, b.telefon, b.chet_el, y.roli,
       y.holat_turi,
       CASE y.holat_turi WHEN 'dam_olish' THEN 'Dam olmoqda' ELSE 'Davolanmoqda' END AS holat_turi_matn,
       x.raqam AS xona, k.raqam AS koyka, bo.nomi AS bolim,
       (y.koyka_id IS NOT NULL) AS xonada,
       y.kirish_sana, y.kirish_vaqt, y.reja_chiqish,
       (current_date - y.kirish_sana + 1) AS kun,
       y.avvalgi_summa + y.summa + y.xona_summa AS kurs_summa,
       hisob(y.id)    AS umumiy,
       tolangan(y.id) AS tolangan,
       qarz(y.id)     AS qarz
FROM yotqizishlar y
  JOIN bemorlar b   ON b.id = y.bemor_id
  LEFT JOIN koykalar k  ON k.id = y.koyka_id
  LEFT JOIN xonalar x   ON x.id = k.xona_id
  LEFT JOIN bolimlar bo ON bo.id = x.bolim_id
WHERE y.holat = 'yotmoqda';

-- ------------------------------------------------------------
-- 9. CHEK — nominal summaga avvalgi bosqichlar ham qo'shiladi
--    13_chek.sql dagi variantni SUPERSEDE qiladi (izoh uchun,
--    hisob/qarz mantig'i o'zgarmaydi — ular allaqachon hisob()
--    orqali to'g'ri chiqadi).
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

  kunlik        numeric,      -- joriy bosqichning kunlik narxi
  kurs_summa    numeric,      -- jami nominal (avvalgi bosqichlar + joriy)
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

    CASE
      WHEN y.holat_turi = 'dam_olish' THEN y.dam_kunlik_narx
      WHEN (SELECT qiymat FROM tariflar WHERE kalit = 'kurs_kun') > 0
        THEN round((y.summa + y.xona_summa)
                   / (SELECT qiymat FROM tariflar WHERE kalit = 'kurs_kun'))
    END,
    y.avvalgi_summa + y.summa + y.xona_summa,
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
  y.avvalgi_summa + y.summa + y.xona_summa AS kurs_summa,
  hisob(y.id)                AS umumiy,
  tolangan(y.id)             AS tolangan,
  qarz(y.id)                 AS qolgan_qarz
FROM tolovlar t
  JOIN yotqizishlar y   ON y.id = t.yotqizish_id
  JOIN bemorlar b       ON b.id = y.bemor_id
  LEFT JOIN koykalar k  ON k.id = y.koyka_id
  LEFT JOIN xonalar x   ON x.id = k.xona_id
  LEFT JOIN bolimlar bo ON bo.id = x.bolim_id;

-- ------------------------------------------------------------
-- 10. SOZLAMALAR KO'RINISHI — dam olish narxi ham ko'rinsin
-- ------------------------------------------------------------
DROP VIEW IF EXISTS v_xona_narxlari;
CREATE VIEW v_xona_narxlari
WITH (security_invoker = on) AS
SELECT t.nomi                AS turi,
       t.narx,
       t.dam_olish_narxi,
       t.tartib,
       count(DISTINCT x.id)  AS xona_soni,
       count(k.id)           AS koyka_soni,
       string_agg(DISTINCT x.raqam, ', ' ORDER BY x.raqam) AS xonalar
FROM xona_turlari t
  LEFT JOIN xonalar x  ON x.turi = t.nomi
  LEFT JOIN koykalar k ON k.xona_id = x.id
GROUP BY t.nomi, t.narx, t.dam_olish_narxi, t.tartib
ORDER BY t.tartib, t.nomi;

-- ------------------------------------------------------------
-- 11. BELGI FUNKSIYASI (07_tekshirish.sql shu orqali biladi)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION dam_olish_ornatildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- 12. anon hech narsaga tegmasin
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 13. TEKSHIRUV
-- ------------------------------------------------------------
SELECT
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='xona_turlari'
                        AND column_name='dam_olish_narxi')
       THEN 'toʻgʻri' ELSE 'XATO' END AS "dam_olish_narxi ustuni",
  CASE WHEN (SELECT count(*) FROM information_schema.columns
              WHERE table_schema='public' AND table_name='yotqizishlar'
                AND column_name IN ('holat_turi','davr_boshi','avvalgi_summa','dam_kunlik_narx')) = 4
       THEN 'toʻgʻri' ELSE 'XATO' END AS "yotqizishlar 4 ustun",
  CASE WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public'
                AND p.proname IN ('davr_hisob','holat_ozgartir','bemorni_qarovchiga',
                                  'xona_turi_dam_narx','dam_olish_ornatildi')) = 5
       THEN 'toʻgʻri' ELSE 'XATO' END AS "5 ta yangi funksiya";

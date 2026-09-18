-- ============================================================
--  30_bolim_narxlari.sql — BO'LIM QO'SHISH + BO'LIMGA QARAB NARX
--  01..29 dan KEYIN. Idempotent.
--
--  MIJOZ TALABI
--    1. Mijoz o'zi yangi bo'lim qo'sha olishi kerak (masalan
--       "Erkaklar bo'limi"ga o'xshash yangi bo'lim) — nomi va
--       jinsini kiritib. Mavjud bo'limni ham tahrirlay olishi kerak.
--    2. Xonani o'zi qo'shgan bo'limga biriktira olishi kerak —
--       BU ALLAQACHON ISHLAYDI: xona_tahrir() (26_tahrir_ochirish.sql)
--       istalgan bolim_id'ga xona ko'chirishga ruxsat beradi, va
--       frontend'dagi bo'lim tanlash ro'yxati bazadan (db.bolimlar())
--       dinamik o'qiladi — yangi qo'shilgan bo'lim avtomatik
--       ro'yxatda chiqadi. Shu qism uchun kod o'zgarishi shart emas.
--    3. Bemor narxi (kattalar/yosh toifalari) endi BO'LIMGA QARAB
--       farqlanishi kerak — har bir bo'lim o'z narxini belgilaydi.
--       Qarovchi va farzand narxi esa BIR XIL (umumiy) qoladi —
--       bo'limdan mustaqil, mijoz bilan tasdiqlangan qaror.
--
--  YECHIM
--    bolim_narxlari — har bir bo'lim uchun 5 ta narx qatori
--    ('yosh_5','yosh_10','yosh_15','kattalar','chet_el'). Yangi
--    bo'lim qo'shilganda, joriy umumiy tariflar qiymatlaridan
--    NUSXA olib avtomatik to'ldiriladi — shunday qilib darhol
--    ishlaydi, keyin admin xohlasa alohida o'zgartiradi.
--
--    narx_hisobla() ga YANGI ixtiyoriy parametr qo'shiladi:
--    p_bolim_id (oxirida, DEFAULT NULL) — shuning uchun signaturasi
--    "o'zgarmaydi" (eski 3 argumentli chaqiruvlar ham ishlayveradi).
--    Faqat p_roli='bemor' bo'lganda va bolim_narxlari'da mos qator
--    topilganda ishlatiladi; farzand/qarovchi va bo'lim ko'rsatilmagan
--    hollarda — ESKICHA, umumiy tariflar jadvalidan.
--
--    bemor_joylashtir(), qarovchini_bemorga(), holat_ozgartir() —
--    UCHALASINING TASHQI SIGNATURASI O'ZGARMAYDI, faqat ichkarida
--    endi xonaning bo'limini topib narx_hisobla()ga uzatadi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='qarovchi_bemor_tuzatildi') THEN
    RAISE EXCEPTION 'Avval 29_qarovchi_bemor_tuzatish.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. BO'LIM NARXLARI JADVALI
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bolim_narxlari (
  bolim_id smallint NOT NULL REFERENCES bolimlar(id) ON DELETE CASCADE,
  kalit    text NOT NULL,
  qiymat   numeric(12,0) NOT NULL DEFAULT 0,
  PRIMARY KEY (bolim_id, kalit)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bolim_narxlari_kalit_ck') THEN
    ALTER TABLE bolim_narxlari ADD CONSTRAINT bolim_narxlari_kalit_ck
      CHECK (kalit IN ('yosh_5','yosh_10','yosh_15','kattalar','chet_el'));
  END IF;
END $$;

ALTER TABLE bolim_narxlari ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS korish ON bolim_narxlari;
CREATE POLICY korish ON bolim_narxlari FOR SELECT USING (joriy_rol() IS NOT NULL);

-- Mavjud bo'limlarni joriy UMUMIY narxlar bilan urug'lantirish —
-- shu bilan migratsiyadan keyin HECH NARSA o'zgarmaydi (hamma
-- bo'lim xuddi hozirgidek, umumiy narxda qoladi, admin xohlasa
-- keyin alohida-alohida o'zgartiradi).
INSERT INTO bolim_narxlari (bolim_id, kalit, qiymat)
SELECT b.id, t.kalit, t.qiymat
FROM bolimlar b CROSS JOIN tariflar t
WHERE t.kalit IN ('yosh_5','yosh_10','yosh_15','kattalar','chet_el')
ON CONFLICT (bolim_id, kalit) DO NOTHING;

-- ------------------------------------------------------------
-- 2. BO'LIM QO'SHISH — mijoz o'zi "Erkaklar bo'limi"ga o'xshash
--    yangi bo'lim yarata oladi. Faqat super_admin (Admin).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bolim_qosh(p_nomi text, p_jins bolim_jinsi)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_id int; v_tartib smallint; v_nomi text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'boʻlim qoʻshish');

  v_nomi := btrim(COALESCE(p_nomi, ''));
  IF v_nomi = '' THEN
    RAISE EXCEPTION 'Boʻlim nomini kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM bolimlar WHERE nomi = v_nomi) THEN
    RAISE EXCEPTION 'Shu nomli boʻlim allaqachon bor.' USING ERRCODE = 'unique_violation';
  END IF;

  SELECT COALESCE(max(tartib), 0) + 1 INTO v_tartib FROM bolimlar;

  INSERT INTO bolimlar (nomi, jins, tartib)
  VALUES (v_nomi, p_jins, v_tartib)
  RETURNING id INTO v_id;

  -- Yangi bo'lim darhol ishlashi uchun — joriy umumiy narxlardan
  -- nusxa. Admin xohlasa keyin Sozlamalardan alohida o'zgartiradi.
  INSERT INTO bolim_narxlari (bolim_id, kalit, qiymat)
  SELECT v_id, t.kalit, t.qiymat FROM tariflar t
  WHERE t.kalit IN ('yosh_5','yosh_10','yosh_15','kattalar','chet_el');

  RETURN v_id;
END $$;

-- ------------------------------------------------------------
-- 3. BO'LIMNI TAHRIRLASH — nomi va jinsini o'zgartirish.
--    Jinsi 'aralash'dan boshqasiga o'zgartirilsa — shu bo'limda
--    hozir boshqa jinsdagi bemor yotmaganiga ishonch hosil
--    qilinadi (trg_jins_tekshir bilan bir xil mantiq).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bolim_tahrir(p_bolim_id int, p_nomi text, p_jins bolim_jinsi)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_nomi text; v_boshqa text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'boʻlimni tahrirlash');

  IF NOT EXISTS (SELECT 1 FROM bolimlar WHERE id = p_bolim_id) THEN
    RAISE EXCEPTION 'Boʻlim topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  v_nomi := btrim(COALESCE(p_nomi, ''));
  IF v_nomi = '' THEN
    RAISE EXCEPTION 'Boʻlim nomini kiriting.' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM bolimlar WHERE nomi = v_nomi AND id <> p_bolim_id) THEN
    RAISE EXCEPTION 'Shu nomli boʻlim allaqachon bor.' USING ERRCODE = 'unique_violation';
  END IF;

  IF p_jins <> 'aralash' THEN
    SELECT string_agg(DISTINCT bm.familiya || ' ' || bm.ism, ', ') INTO v_boshqa
    FROM yotqizishlar y
      JOIN koykalar k  ON k.id = y.koyka_id
      JOIN xonalar x   ON x.id = k.xona_id
      JOIN bemorlar bm ON bm.id = y.bemor_id
    WHERE x.bolim_id = p_bolim_id AND y.holat = 'yotmoqda'
      AND bm.jins::text <> p_jins::text;

    IF v_boshqa IS NOT NULL THEN
      RAISE EXCEPTION 'Bu boʻlimda hozir boshqa jinsdagi bemor(lar) bor (%). Avval ularni koʻchiring yoki chiqaring.', v_boshqa
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  UPDATE bolimlar SET nomi = v_nomi, jins = p_jins WHERE id = p_bolim_id;
END $$;

-- ------------------------------------------------------------
-- 4. BO'LIM NARXINI O'ZGARTIRISH — "narx" konvensiyasiga mos,
--    faqat super_admin, narx_tarixi'ga yoziladi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bolim_narx_ozgartir(p_bolim_id int, p_kalit text, p_narx numeric)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_eski numeric; v_nomi text;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'boʻlim narxini oʻzgartirish');

  IF p_kalit NOT IN ('yosh_5','yosh_10','yosh_15','kattalar','chet_el') THEN
    RAISE EXCEPTION 'Notoʻgʻri narx kaliti: %', p_kalit USING ERRCODE = 'check_violation';
  END IF;
  IF p_narx IS NULL OR p_narx < 0 THEN
    RAISE EXCEPTION 'Narx manfiy boʻlishi mumkin emas.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT nomi INTO v_nomi FROM bolimlar WHERE id = p_bolim_id;
  IF v_nomi IS NULL THEN
    RAISE EXCEPTION 'Boʻlim topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  SELECT qiymat INTO v_eski FROM bolim_narxlari WHERE bolim_id = p_bolim_id AND kalit = p_kalit;

  INSERT INTO bolim_narxlari (bolim_id, kalit, qiymat) VALUES (p_bolim_id, p_kalit, p_narx)
    ON CONFLICT (bolim_id, kalit) DO UPDATE SET qiymat = EXCLUDED.qiymat;

  INSERT INTO narx_tarixi (tur, nomi, eski, yangi, kim)
  VALUES ('bolim_narxi', v_nomi || ' — ' || p_kalit, v_eski, p_narx, joriy_fish());

  RETURN p_narx;
END $$;

-- ------------------------------------------------------------
-- 5. NARX_HISOBLA — yangi ixtiyoriy p_bolim_id (oxirida, DEFAULT
--    NULL) qo'shiladi. Signaturasi kengayadi, lekin eski 3
--    argumentli chaqiruvlar ham xuddi avvalgidek ishlayveradi.
--
--    Faqat p_roli='bemor' VA p_bolim_id berilganda VA o'sha
--    bo'limda mos narx borida ishlatiladi — aks holda ESKICHA,
--    umumiy tariflardan. Qarovchi va farzand — bo'limdan
--    mustaqil, umumiy narxda qoladi (mijoz bilan tasdiqlangan).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION narx_hisobla(
  p_yosh int, p_chet_el bool, p_roli shaxs_roli, p_bolim_id smallint DEFAULT NULL
) RETURNS numeric LANGUAGE plpgsql STABLE AS $$
DECLARE v numeric; v_kalit text; v_chet numeric;
BEGIN
  IF p_roli = 'qarovchi' THEN
    SELECT qiymat INTO v FROM tariflar WHERE kalit = 'qarovchi';
    RETURN v;
  END IF;

  v_kalit := CASE
    WHEN p_yosh <= 5  THEN 'yosh_5'
    WHEN p_yosh <= 10 THEN 'yosh_10'
    WHEN p_yosh <= 15 THEN 'yosh_15'
    ELSE 'kattalar'
  END;

  v := NULL;
  IF p_roli = 'bemor' AND p_bolim_id IS NOT NULL THEN
    SELECT qiymat INTO v FROM bolim_narxlari WHERE bolim_id = p_bolim_id AND kalit = v_kalit;
  END IF;
  IF v IS NULL THEN
    SELECT qiymat INTO v FROM tariflar WHERE kalit = v_kalit;
  END IF;

  IF p_chet_el THEN
    v_chet := NULL;
    IF p_roli = 'bemor' AND p_bolim_id IS NOT NULL THEN
      SELECT qiymat INTO v_chet FROM bolim_narxlari WHERE bolim_id = p_bolim_id AND kalit = 'chet_el';
    END IF;
    IF v_chet IS NULL THEN
      SELECT qiymat INTO v_chet FROM tariflar WHERE kalit = 'chet_el';
    END IF;
    v := v + v_chet;
  END IF;

  RETURN v;
END $$;

-- ------------------------------------------------------------
-- 6. BEMOR_JOYLASHTIR — signaturasi O'ZGARMAYDI. Ichkarida
--    xonaning bo'limi topilib narx_hisobla()ga uzatiladi.
--    (11_xona_turlari.sql dagi variantni SUPERSEDE qiladi.)
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
  v_xona int; v_bolim smallint; v_mavjud int; v_raqam text;
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

  -- ⭐ Xona puli: faqat mustaqil bemor toʻlaydi.
  --    Farzand va qarovchi — 0 (bemor xonani ular uchun ham band qilgan).
  --    Shu yerda topilgan xonaning boʻlimi narx_hisobla()ga ham beriladi.
  IF p_koyka IS NOT NULL AND p_roli = 'bemor' THEN
    SELECT k.xona_id INTO v_xona FROM koykalar k WHERE k.id = p_koyka;
    v_xona_summa := xona_narxi(v_xona);
  END IF;

  IF v_xona IS NOT NULL THEN
    SELECT bolim_id INTO v_bolim FROM xonalar WHERE id = v_xona;
  END IF;

  v_summa := narx_hisobla(p_yosh, p_chet_el, p_roli, v_bolim);

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

-- ------------------------------------------------------------
-- 7. QAROVCHINI_BEMORGA — signaturasi O'ZGARMAYDI (29 bilan bir
--    xil), faqat yangi kurs narxini hisoblashda endi xonaning
--    boʻlimi ham hisobga olinadi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION qarovchini_bemorga(p_yotqizish int, p_yangi_chiqish date DEFAULT NULL)
RETURNS TABLE (
  qarovchi_kuni   int,
  qarovchi_puli   numeric,
  bemor_puli      numeric,
  yangi_summa     numeric,
  yangi_reja      date
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  y yotqizishlar%ROWTYPE;
  v_kurs numeric; v_kun int; v_joriy numeric; v_qarz numeric;
  v_yosh int; v_chet boolean; v_yangi numeric; v_reja date; v_bolim smallint;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'qarovchini bemorga aylantirish');

  SELECT * INTO y FROM yotqizishlar
   WHERE id = p_yotqizish AND roli = 'qarovchi' AND holat = 'yotmoqda'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bu yozuv qarovchi emas yoki allaqachon chiqarilgan.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
  v_kun := GREATEST(1, current_date - y.davr_boshi + 1);
  v_joriy := davr_hisob(y.holat_turi, v_kun, y.summa, y.xona_summa, y.dam_kunlik_narx, v_kurs);

  v_qarz := GREATEST(0, COALESCE(y.avvalgi_summa, 0) + v_joriy - tolangan(p_yotqizish));
  IF v_qarz > 0 THEN
    RAISE EXCEPTION 'Qarovchini bemorga aylantirib boʻlmaydi. Qarovchilik bosqichi uchun toʻlanmagan qarz bor: % soʻm. Avval toʻlovni qabul qiling.',
      pul_matn(v_qarz)
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT bemor_yoshi(b), b.chet_el INTO v_yosh, v_chet
  FROM bemorlar b WHERE b.id = y.bemor_id;

  IF y.koyka_id IS NOT NULL THEN
    SELECT x.bolim_id INTO v_bolim
    FROM koykalar k JOIN xonalar x ON x.id = k.xona_id
    WHERE k.id = y.koyka_id;
  END IF;

  v_yangi := narx_hisobla(v_yosh, v_chet, 'bemor'::shaxs_roli, v_bolim);
  v_reja  := COALESCE(p_yangi_chiqish, current_date + v_kurs::int);

  UPDATE yotqizishlar SET
    roli            = 'bemor',
    avvalgi_summa   = COALESCE(y.avvalgi_summa, 0) + v_joriy,
    holat_turi      = 'davolanish',
    davr_boshi      = current_date,
    summa           = v_yangi,
    xona_summa      = 0,
    dam_kunlik_narx = NULL,
    reja_chiqish    = v_reja,
    izoh = COALESCE(izoh || ' | ', '') ||
      format('Qarovchi → Bemor (%s kun qarovchi: %s soʻm). Kim: %s',
             v_kun, pul_matn(v_joriy), joriy_fish())
   WHERE id = p_yotqizish;

  RETURN QUERY SELECT v_kun, v_joriy, v_yangi, v_joriy + v_yangi, v_reja;
END $$;

-- ------------------------------------------------------------
-- 8. HOLAT_OZGARTIR — signaturasi O'ZGARMAYDI (28 bilan bir xil),
--    faqat "davolanish"ga qaytishda xonaning boʻlimi hisobga
--    olinadi.
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
  v_yosh int; v_chet boolean; v_bolim smallint;
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

  v_qarz := GREATEST(0, COALESCE(y.avvalgi_summa, 0) + v_joriy - tolangan(p_yotqizish));
  IF v_qarz > 0 THEN
    RAISE EXCEPTION 'Holatni oʻzgartirib boʻlmaydi. Joriy bosqich (%s, %s kun) uchun toʻlanmagan qarz bor: % soʻm. Avval toʻlovni qabul qiling.',
      y.holat_turi, v_kun, pul_matn(v_qarz)
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT x.bolim_id INTO v_bolim
  FROM koykalar k JOIN xonalar x ON x.id = k.xona_id
  WHERE k.id = y.koyka_id;

  IF p_yangi_holat = 'davolanish' THEN
    SELECT bemor_yoshi(b), b.chet_el INTO v_yosh, v_chet
    FROM bemorlar b WHERE b.id = y.bemor_id;
    v_yangi_summa := narx_hisobla(v_yosh, v_chet, 'bemor'::shaxs_roli, v_bolim);
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
-- 9. BELGI FUNKSIYASI (07_tekshirish.sql shu orqali biladi)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION bolim_narxlari_ornatildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- 10. anon hech narsaga tegmasin
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 11. TEKSHIRUV
-- ------------------------------------------------------------
SELECT
  CASE WHEN to_regclass('public.bolim_narxlari') IS NOT NULL
       THEN 'toʻgʻri' ELSE 'XATO' END AS "bolim_narxlari jadvali",
  CASE WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public'
                AND p.proname IN ('bolim_qosh','bolim_tahrir','bolim_narx_ozgartir',
                                  'bolim_narxlari_ornatildi')) = 4
       THEN 'toʻgʻri' ELSE 'XATO' END AS "4 ta yangi funksiya",
  CASE WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public' AND p.proname='narx_hisobla' AND p.pronargs=4) = 1
       THEN 'toʻgʻri' ELSE 'XATO' END AS "narx_hisobla 4-argumentli";

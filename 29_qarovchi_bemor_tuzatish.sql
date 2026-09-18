-- ============================================================
--  29_qarovchi_bemor_tuzatish.sql — QAROVCHI -> BEMOR TUZATISH
--  01..28 dan KEYIN. Idempotent.
--
--  MUAMMO
--    28_dam_olish.sql yangi hisob modelini kiritdi: har bir bosqich
--    (davolanish/dam olish) o'zining davr_boshi'siga ega, muzlagan
--    bosqichlar avvalgi_summa'ga qo'shiladi, hisob() esa faqat
--    davr_boshi'dan buyon o'tgan kunlarni hisoblaydi (davr_hisob()).
--
--    08_hamrohlar.sql dagi ESKI qarovchini_bemorga() funksiyasi bu
--    modeldan XABARSIZ qoldi: u qarovchilik puli va yangi bemor
--    kursi narxini bittasiga (summa) qo'shib qo'yaverar, lekin
--    davr_boshi'ni BUGUNGA tiklamas edi. Natijada:
--      - hisob() yangi bemor kursini "necha kun bo'ldi" deb
--        ORIGINAL kirish sanasidan (ya'ni qarovchi bo'lib kelgan
--        kunidan) hisoblab, narxni NOTO'G'RI (juda kam yoki juda
--        ko'p, kursning "tugagani"ga qarab) chiqarardi — YANGI
--        bemor kursi xuddi bugun boshlagandek emas, boshida
--        allaqachon necha kun o'tgandek hisoblanardi.
--      - qarz turib ham (yoki qarzsiz ham farqsiz) aylantirish
--        mumkin edi — 28-fayldagi boshqa ikkita aylantirish
--        funksiyasi (bemorni_qarovchiga, holat_ozgartir) esa qarz
--        bo'lsa xatolik berib to'xtaydi. Muvofiqlik yo'q edi.
--
--  YECHIM
--    qarovchini_bemorga() endi xuddi bemorni_qarovchiga() va
--    holat_ozgartir() kabi ishlaydi:
--      1. Joriy (qarovchilik) bosqichini davr_hisob() orqali
--         BUGUNGACHA hisoblaydi.
--      2. Qarz bo'lsa — XATOLIK, aylantirmaydi (avval to'lov kerak).
--      3. Qarzsiz bo'lsa: hisoblangan summani avvalgi_summaga
--         qo'shib muzlatadi, YANGI bosqichni (roli=bemor,
--         holat_turi=davolanish, davr_boshi=bugun) boshlaydi —
--         endi yangi bemor kursi xuddi BOSHQA har qanday oddiy
--         bemor kabi, 1-kunidan hisoblanadi.
--
--    Qaytariladigan qiymatlar (frontend uchun) o'zgarmaydi —
--    src/lib/supabase.js va Bemorlar.jsx ni tahrirlash SHART EMAS.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='dam_olish_ornatildi') THEN
    RAISE EXCEPTION 'Avval 28_dam_olish.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- QAROVCHI -> BEMOR — davr_hisob() modeliga moslashtirilgan
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
  v_yosh int; v_chet boolean; v_yangi numeric; v_reja date;
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

  -- ⭐ Xuddi bemorni_qarovchiga() / holat_ozgartir() kabi: qarz
  --    turib bosqich almashtirilmaydi — avval to'lov qabul qilinadi.
  v_qarz := GREATEST(0, COALESCE(y.avvalgi_summa, 0) + v_joriy - tolangan(p_yotqizish));
  IF v_qarz > 0 THEN
    RAISE EXCEPTION 'Qarovchini bemorga aylantirib boʻlmaydi. Qarovchilik bosqichi uchun toʻlanmagan qarz bor: % soʻm. Avval toʻlovni qabul qiling.',
      pul_matn(v_qarz)
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT bemor_yoshi(b), b.chet_el INTO v_yosh, v_chet
  FROM bemorlar b WHERE b.id = y.bemor_id;
  v_yangi := narx_hisobla(v_yosh, v_chet, 'bemor'::shaxs_roli);
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

  -- Qaytariladigan ustunlar eskisi bilan bir xil ma'noda:
  -- qarovchi_puli = qarovchilik bosqichi puli, bemor_puli = yangi
  -- kurs narxi, yangi_summa = ikkalasining yig'indisi (ko'rsatish
  -- uchun — bazada ular endi avvalgi_summa/summa'ga ALOHIDA yoziladi).
  RETURN QUERY SELECT v_kun, v_joriy, v_yangi, v_joriy + v_yangi, v_reja;
END $$;

-- ------------------------------------------------------------
-- BELGI FUNKSIYASI (07_tekshirish.sql shu orqali biladi)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION qarovchi_bemor_tuzatildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- anon hech narsaga tegmasin
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- TEKSHIRUV
-- ------------------------------------------------------------
SELECT
  CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname='qarovchi_bemor_tuzatildi')
       THEN 'toʻgʻri' ELSE 'XATO' END AS "tuzatish qo'llandi";

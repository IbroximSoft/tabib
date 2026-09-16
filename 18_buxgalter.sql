-- ============================================================
--  18_buxgalter.sql — BUXGALTER HUQUQLARINI TORAYTIRISH
--  01, 03, 05, 06, 08..17 dan KEYIN. Idempotent.
--
--  Buxgalterning ishi — kassa. Shuning uchun undan olib
--  tashlanadi:
--
--    narxni o'zgartirish   -> faqat super_admin
--    xona narxi            -> faqat super_admin
--
--  Qoladi:
--    to'lov qabul qilish, chek chiqarish, bemorni chiqarish
--    (qarzi yopilgan bo'lsa), hamma narsani ko'rish
--
--  Bemorni chiqarish ataylab buxgalterda qoldirilgan: pulni u
--  qabul qiladi, demak hisobni ham u yopadi. Fayl uni qaytarib
--  ham qo'ya oladi — avvalgi variantda olib tashlangan edi.
--
--  QANDAY ISHLAYDI: funksiyalarning ichki mantig'iga TEGILMAYDI.
--  Bazadan funksiyaning tayyor matni olinadi va faqat huquq
--  ro'yxati tahrirlanadi. Shu sababli bu fayl kelajakda
--  funksiyalar o'zgarsa ham ishlayveradi va hisob-kitob
--  mantig'ini eski holiga qaytarib yubormaydi.
--
--  Ilova tomonida ham shunday: buxgalterga Dashboard, Bemorlar
--  va To'lovlar sahifalari ko'rinadi, boshqasi yo'q.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='xodim_qosh') THEN
    RAISE EXCEPTION 'Avval 17_xodimlar.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- MARKER
--   09 va 11 fayllari qayta ishga tushirilsa, shu funksiya
--   borligini ko'rib, huquqlarni eski holiga qaytarmaydi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION buxgalter_toraytirildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- HUQUQ RO'YXATLARINI TO'G'RILASH
--   narx funksiyalaridan  'buxgalter' OLIB TASHLANADI
--   bemor_chiqar() ga     'buxgalter' QAYTARILADI
-- ------------------------------------------------------------
DO $$
DECLARE
  r        record;
  v_manba  text;
  v_yangi  text;
  v_soni   int := 0;

  -- narx funksiyalari: buxgalter OLIB TASHLANADI
  v_narx text[] := ARRAY[
    'tarif_ozgartir',      -- 09: kurs narxlari
    'xona_narx_ozgartir',  -- 09: bitta xona narxi (11 dan keyin yo'q)
    'xona_narx_sigim',     -- 09: sig'im bo'yicha (11 dan keyin yo'q)
    'xona_turi_narx'       -- 11: xona turi narxi
  ];
BEGIN
  -- ---------- 1. Narxlar: faqat super_admin ----------
  FOR r IN
    SELECT p.oid, p.proname,
           pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = ANY(v_narx)
  LOOP
    v_manba := pg_get_functiondef(r.oid);
    v_yangi := replace(v_manba,
      'ARRAY[''super_admin'',''buxgalter'']::rol_turi[]',
      'ARRAY[''super_admin'']::rol_turi[]');

    IF v_yangi = v_manba THEN
      CONTINUE;                       -- bu funksiyada buxgalter yo'q ekan
    END IF;

    EXECUTE v_yangi;
    v_soni := v_soni + 1;
    RAISE NOTICE 'Toraytirildi: %(%)', r.proname, r.args;
  END LOOP;

  -- ---------- 2. Bemorni chiqarish: buxgalter QAYTARILADI ----------
  --   Bu fayl avvalgi variantida uni olib tashlagan edi.
  FOR r IN
    SELECT p.oid, p.proname,
           pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'bemor_chiqar'
  LOOP
    v_manba := pg_get_functiondef(r.oid);
    IF position('''buxgalter''' in v_manba) > 0 THEN
      CONTINUE;                       -- allaqachon bor
    END IF;
    v_yangi := replace(v_manba,
      'ARRAY[''super_admin'',''administrator'']::rol_turi[]',
      'ARRAY[''super_admin'',''administrator'',''buxgalter'']::rol_turi[]');

    IF v_yangi = v_manba THEN
      RAISE NOTICE 'bemor_chiqar() huquq ro''yxati tanilmadi — qo''lda tekshiring.';
      CONTINUE;
    END IF;

    EXECUTE v_yangi;
    v_soni := v_soni + 1;
    RAISE NOTICE 'Qaytarildi: buxgalter -> %(%)', r.proname, r.args;
  END LOOP;

  IF v_soni = 0 THEN
    RAISE NOTICE 'Huquqlar allaqachon joyida — o''zgarish kiritilmadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- TEKSHIRUV — huquqlar joyidami
--   "tekshiruv" ustunida hammasi "to'g'ri" bo'lishi kerak.
-- ------------------------------------------------------------
SELECT p.proname AS "funksiya",
       CASE WHEN pg_get_functiondef(p.oid) LIKE '%''buxgalter''%'
            THEN 'buxgalter BOR' ELSE 'buxgalter yoʻq' END AS "holati",
       CASE
         WHEN p.proname = 'bemor_chiqar'
           THEN CASE WHEN pg_get_functiondef(p.oid) LIKE '%''buxgalter''%'
                     THEN 'toʻgʻri' ELSE '<<< XATO: boʻlishi kerak' END
         ELSE CASE WHEN pg_get_functiondef(p.oid) LIKE '%''buxgalter''%'
                   THEN '<<< XATO: boʻlmasligi kerak' ELSE 'toʻgʻri' END
       END AS "tekshiruv"
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('tarif_ozgartir','xona_narx_ozgartir','xona_narx_sigim',
                    'xona_turi_narx','bemor_chiqar')
ORDER BY 1;

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

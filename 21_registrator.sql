-- ============================================================
--  21_registrator.sql — REGISTRATOR HUQUQLARINI TORAYTIRISH
--  01, 03, 05, 06, 08..20 dan KEYIN. Idempotent.
--
--  Registratorning ishi — qabul va joylashtirish:
--    bemor qo'shish, xonaga joylashtirish, xonani almashtirish,
--    muddatni uzaytirish, bron qo'yish va bronni boshqarish.
--
--  Undan olib tashlanadi:
--    1. bemorni chiqarish  -> super_admin va buxgalter
--       (chiqarishda qarz tekshiriladi — bu kassaning ishi)
--    2. to'lovlar yozuvini KO'RISH -> RLS orqali yopiladi
--       (kim qancha to'laganini registrator bilmasin)
--
--  DIQQAT — nima YOPILMAYDI
--    v_yotqizishlar dagi "qarz", "tolangan", "umumiy" ustunlari
--    SECURITY DEFINER funksiyalar orqali hisoblanadi, shuning
--    uchun ular bazada ochiq qolaveradi. Ilova ularni
--    registratorga ko'rsatmaydi ('pul' huquqi yo'q). Ularni
--    bazada ham yopish uchun har bir rolga alohida ko'rinish
--    kerak bo'ladi — bu butun hisob-kitobni qayta qurishni
--    talab qiladi, shuning uchun hozir qilinmadi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='bron_xona') THEN
    RAISE EXCEPTION 'Avval 20_bron_xona.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- MARKER
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION registrator_toraytirildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- 1. BEMORNI CHIQARISH — registrator emas
--    Funksiyaning ichki mantig'iga tegilmaydi: tayyor matni
--    olinadi va faqat huquq ro'yxati tahrirlanadi.
-- ------------------------------------------------------------
DO $$
DECLARE
  r       record;
  v_manba text;
  v_yangi text;
BEGIN
  FOR r IN
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'bemor_chiqar'
  LOOP
    v_manba := pg_get_functiondef(r.oid);
    v_yangi := v_manba;

    v_yangi := replace(v_yangi,
      'ARRAY[''super_admin'',''administrator'',''buxgalter'']::rol_turi[]',
      'ARRAY[''super_admin'',''buxgalter'']::rol_turi[]');
    v_yangi := replace(v_yangi,
      'ARRAY[''super_admin'',''administrator'']::rol_turi[]',
      'ARRAY[''super_admin'',''buxgalter'']::rol_turi[]');

    IF v_yangi = v_manba THEN
      RAISE NOTICE 'bemor_chiqar() allaqachon toʻgʻri — oʻzgartirilmadi.';
    ELSE
      EXECUTE v_yangi;
      RAISE NOTICE 'bemor_chiqar(%) — registrator olib tashlandi.', r.args;
    END IF;
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 2. TO'LOVLAR YOZUVI — registrator ko'rmasin
--    v_tolovlar security_invoker bilan ishlaydi, shuning uchun
--    jadvalning o'zidagi siyosat u orqali ham kuchga kiradi.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS korish ON tolovlar;
CREATE POLICY korish ON tolovlar FOR SELECT
  USING (joriy_rol() IN ('super_admin', 'buxgalter', 'viewer'));

-- ------------------------------------------------------------
-- TEKSHIRUV
-- ------------------------------------------------------------
SELECT 'bemor_chiqar' AS "nima",
       CASE WHEN pg_get_functiondef(p.oid) LIKE '%''administrator''%'
            THEN '<<< XATO: registrator bor' ELSE 'toʻgʻri — registrator yoʻq' END AS "holati"
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'bemor_chiqar'
UNION ALL
SELECT 'tolovlar koʻrish',
       CASE WHEN pg_get_expr(pol.polqual, pol.polrelid) LIKE '%administrator%'
            THEN '<<< XATO: registrator koʻradi' ELSE 'toʻgʻri — registrator koʻrmaydi' END
FROM pg_policy pol JOIN pg_class c ON c.oid = pol.polrelid
WHERE c.relname = 'tolovlar' AND pol.polname = 'korish';

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

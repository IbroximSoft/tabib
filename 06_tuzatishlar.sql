-- ============================================================
--  06_tuzatishlar.sql — xavfsizlik va hisob aniqligi tuzatishlari
--  01, 03, 05 dan KEYIN ishga tushiriladi. Qayta-qayta ishga
--  tushirsa ham xavfsiz (idempotent).
--
--  Nimani tuzatadi:
--   1. RLS cheksiz rekursiyasi — login'dan keyin "rol berilmagan"
--      xatosi (aslida baza xatosi edi).
--   2. View'lar RLS ni chetlab o'tishi — anon kalit bilan barcha
--      bemor ma'lumotlari ochiq edi.
--   3. SECURITY DEFINER funksiyalarda search_path yo'qligi.
--   4. Xona sig'imi noto'g'ri sanalishi (dublikat JOIN).
--   5. "Muddati o'tgan, tasdiqlanmagan" bemor tushunchasi —
--      ovqat hisobi va koyka bandligi endi bir xil javob beradi.
--   6. Qarzi bor bemorni rasman chiqarish (super_admin, sabab bilan).
-- ============================================================

-- ------------------------------------------------------------
-- 0. BAZA QAYSI BOSQICHDA? (09-12 fayllari ishga tushganmi?)
--
--    Bu fayldagi ba'zi funksiyalar keyinchalik 09, 10, 11, 12
--    fayllarida QAYTA yozilgan (mijoz qarorlari bo'yicha).
--    Agar 06 ni qayta ishga tushirsak, u eski variantlarni
--    tiklab, yangi qoidalarni jimgina bekor qilib qo'yadi:
--      * qarz bilan chiqarish qaytib keladi (bekor qilingan edi)
--      * kunlik hisob yo'qoladi (to'liq kurs puli qaytadi)
--      * xona puli hamrohlardan ham olinadi
--    Shuning uchun har bir shunday bo'lim shartli ishlaydi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION migratsiya_bosqichi() RETURNS int
LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'tolov_qosh'
                    AND p.pronargs = 5)                      THEN 13
    WHEN to_regclass('public.v_koykalar')   IS NOT NULL THEN 12
    WHEN to_regclass('public.xona_turlari') IS NOT NULL THEN 11
    WHEN EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'v_yotqizishlar'
                    AND column_name = 'kurs_summa')            THEN 10
    WHEN EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'bemorlar'
                    AND column_name = 'hamroh')                THEN 9
    ELSE 0
  END;
$$;

DO $$
BEGIN
  IF migratsiya_bosqichi() > 0 THEN
    RAISE NOTICE 'Bu bazada % -fayl allaqachon ishga tushirilgan — 06 ning eskirgan bo''limlari o''tkazib yuboriladi.',
                 migratsiya_bosqichi();
  END IF;
END $$;

-- ------------------------------------------------------------
-- 1. REKURSIYANI TO'XTATAMIZ
--    joriy_rol() xodimlar jadvalini o'qiydi, xodimlar jadvalining
--    RLS siyosati esa joriy_rol() ni chaqiradi -> cheksiz halqa.
--    Yechim: bu ikki funksiya RLS dan ustun (SECURITY DEFINER).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION joriy_rol() RETURNS rol_turi
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid; v_rol rol_turi;
BEGIN
  BEGIN
    EXECUTE 'SELECT auth.uid()' INTO v_uid;
  EXCEPTION WHEN OTHERS THEN
    v_uid := NULL;
  END;

  IF v_uid IS NOT NULL THEN
    SELECT rol INTO v_rol FROM xodimlar WHERE auth_id = v_uid AND faol;
    RETURN v_rol;
  END IF;

  RETURN NULLIF(current_setting('app.rol', true), '')::rol_turi;
END $$;

CREATE OR REPLACE FUNCTION joriy_fish() RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid; v_fish text;
BEGIN
  BEGIN EXECUTE 'SELECT auth.uid()' INTO v_uid;
  EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;
  IF v_uid IS NOT NULL THEN
    SELECT fish INTO v_fish FROM xodimlar WHERE auth_id = v_uid;
    RETURN v_fish;
  END IF;
  RETURN COALESCE(NULLIF(current_setting('app.fish', true), ''), 'tizim');
END $$;

-- Xodim o'z yozuvini har doim o'qiy olsin (rol berilmagan bo'lsa ham,
-- frontend "siz kimsiz" ni ko'rsata olishi uchun).
DROP POLICY IF EXISTS ozini_korish ON xodimlar;
CREATE POLICY ozini_korish ON xodimlar FOR SELECT
  USING (auth_id = (SELECT auth.uid()));

-- ------------------------------------------------------------
-- 2. SECURITY DEFINER FUNKSIYALARGA search_path
--    Bo'lmasa, search_path ni o'zgartirib olib, funksiya ichidagi
--    jadval nomlarini soxta jadvalga yo'naltirish mumkin.
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND (p.proconfig IS NULL
           OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c
                          WHERE c LIKE 'search_path=%'))
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 3. VIEW'LAR ENDI RLS GA BO'YSUNADI
--    Shu paytgacha view'lar egasi (postgres) nomidan ishlagan va
--    RLS ni butunlay chetlab o'tgan. Ya'ni saytning JS faylidagi
--    ochiq anon kalit bilan istalgan odam bemorlar ro'yxatini,
--    telefon raqamlarini va kassa tushumini yuklab olishi mumkin edi.
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'v' AND c.relname LIKE 'v\_%'
  LOOP
    EXECUTE format('ALTER VIEW public.%I SET (security_invoker = on)', r.relname);
  END LOOP;
END $$;

-- (anon ni yopish fayl OXIRIDA — bu yerda qilinsa, quyida yaratiladigan
--  yangi view'lar standart huquqlar tufayli yana ochilib qoladi.)

-- ------------------------------------------------------------
-- 4. XONA SIG'IMI — dublikat JOIN tufayli noto'g'ri sanalardi
--    (bitta koykada ikki faol yozuv bo'lsa, sig'im ham oshib ketardi)
-- ------------------------------------------------------------
-- 12_xonalar_korinishi.sql bu ko'rinishga bo'lim, ta'mir va bron
-- ma'lumotini qo'shadi. U ishga tushgan bo'lsa, tegmaymiz.
DO $blok4$
BEGIN
IF migratsiya_bosqichi() >= 12 THEN
  RAISE NOTICE '12 ishga tushgan — v_xona_holati o''zgartirilmaydi.';
  RETURN;
END IF;
DROP VIEW IF EXISTS v_xona_holati CASCADE;
EXECUTE $v$
CREATE VIEW v_xona_holati
WITH (security_invoker = on) AS
SELECT x.id, x.raqam, bo.nomi AS bolim, x.turi, x.narx,
       count(DISTINCT k.id)                           AS sigim,
       count(DISTINCT k.id) FILTER (WHERE y.id IS NOT NULL) AS band,
       count(DISTINCT y.id)                           AS faol_yozuv,
       CASE
         WHEN x.tamirlashda THEN 'tamir'
         WHEN count(y.id) = 0 AND EXISTS (
              SELECT 1 FROM bronlar br
              WHERE br.xona_id = x.id AND br.holat = 'kutilmoqda') THEN 'bron'
         WHEN count(y.id) = 0 THEN 'bosh'
         WHEN count(DISTINCT k.id) FILTER (WHERE y.id IS NOT NULL)
              >= count(DISTINCT k.id) THEN 'toliq'
         ELSE 'qisman'
       END AS holat
FROM xonalar x
  JOIN bolimlar bo ON bo.id = x.bolim_id
  LEFT JOIN koykalar k ON k.xona_id = x.id
  LEFT JOIN yotqizishlar y
         ON y.koyka_id = k.id AND y.holat = 'yotmoqda'
GROUP BY x.id, x.raqam, bo.nomi, x.turi, x.narx, x.tamirlashda
$v$;
END $blok4$;

-- v_umumiy va v_bron_konfliktlari CASCADE bilan o'chgan bo'lishi mumkin
CREATE OR REPLACE VIEW v_bron_konfliktlari
WITH (security_invoker = on) AS
SELECT br.id AS bron_id, br.ismi AS bron_bemor, br.kirish AS bron_kirish,
       x.raqam AS xona,
       b.familiya || ' ' || b.ism AS hozirgi_bemor,
       y.reja_chiqish AS hozirgi_chiqish,
       (y.reja_chiqish - br.kirish) AS kun_farq
FROM bronlar br
  JOIN xonalar x ON x.id = br.xona_id
  JOIN koykalar k ON k.xona_id = x.id
  JOIN yotqizishlar y ON y.koyka_id = k.id AND y.holat = 'yotmoqda'
  JOIN bemorlar b ON b.id = y.bemor_id
WHERE br.holat = 'kutilmoqda' AND y.reja_chiqish > br.kirish;

-- ------------------------------------------------------------
-- 5. "TASDIQLANMAGAN" BEMOR
--    Reja muddati o'tgan, lekin chiqarilmagan bemor. Shu paytgacha
--    v_hozir_yotganlar uni sanardi (ovqat ortiqcha), hisobot_kunlik
--    esa sanamasdi — ikki ekran ikki xil son berardi.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_tasdiqlanmagan
WITH (security_invoker = on) AS
SELECT y.id AS yotqizish_id,
       b.familiya || ' ' || b.ism AS fish, b.telefon, b.jins,
       x.raqam AS xona, k.raqam AS koyka,
       y.kirish_sana, y.reja_chiqish,
       (current_date - y.reja_chiqish) AS kechikkan_kun,
       qarz(y.id) AS qarz
FROM yotqizishlar y
  JOIN bemorlar b ON b.id = y.bemor_id
  LEFT JOIN koykalar k ON k.id = y.koyka_id
  LEFT JOIN xonalar x  ON x.id = k.xona_id
WHERE y.holat = 'yotmoqda' AND y.reja_chiqish < current_date;

-- v_xona_holati qayta yaratilgani uchun v_umumiy ham tiklanadi
-- (+ yangi "tasdiqlanmagan" ko'rsatkichi qo'shildi)
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

-- Ovqat hisobi uchun yagona manba. Front endi shuni chaqiradi.
CREATE OR REPLACE FUNCTION ovqat_hisobi(p_sana date DEFAULT current_date)
RETURNS TABLE (
  nonushta bigint, tushlik bigint, kechki bigint, jami bigint,
  tasdiqlanmagan bigint
) LANGUAGE sql STABLE AS $$
  WITH faol AS (
    SELECT y.kirish_sana,
           COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                    y.reja_chiqish) AS tugash
    FROM yotqizishlar y
    WHERE y.holat <> 'bekor'
      AND y.kirish_sana <= p_sana
      AND COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                   y.reja_chiqish) >= p_sana
  )
  SELECT
    count(*) FILTER (WHERE kirish_sana <> p_sana),
    count(*),
    count(*) FILTER (WHERE tugash <> p_sana),
    count(*) FILTER (WHERE kirish_sana <> p_sana)
      + count(*) + count(*) FILTER (WHERE tugash <> p_sana),
    (SELECT count(*) FROM v_tasdiqlanmagan)
  FROM faol;
$$;

-- Tasdiqlanmagan bemor turgan koykaga yangi bemor qo'yib bo'lmasin.
-- (Exclusion constraint buni ushlamaydi: band_davri reja sanasida
--  tugagani uchun koyka "bo'sh" ko'rinib qoladi.)
CREATE OR REPLACE FUNCTION trg_tasdiqlanmagan_tekshir() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_kim text;
BEGIN
  IF NEW.koyka_id IS NULL THEN RETURN NEW; END IF;

  SELECT string_agg(b.familiya || ' ' || b.ism || ' (reja: ' ||
                    to_char(y.reja_chiqish, 'DD.MM.YYYY') || ')', ', ')
    INTO v_kim
  FROM yotqizishlar y JOIN bemorlar b ON b.id = y.bemor_id
  WHERE y.koyka_id = NEW.koyka_id
    AND y.holat = 'yotmoqda'
    AND y.reja_chiqish < current_date
    AND y.id <> COALESCE(NEW.id, -1);

  IF v_kim IS NOT NULL THEN
    RAISE EXCEPTION 'Bu koykada muddati oʻtgan bemor bor: %. Avval uni chiqaring yoki muddatini uzaytiring.', v_kim
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tasdiqlanmagan_tekshir ON yotqizishlar;
CREATE TRIGGER tasdiqlanmagan_tekshir
  BEFORE INSERT OR UPDATE OF koyka_id ON yotqizishlar
  FOR EACH ROW EXECUTE FUNCTION trg_tasdiqlanmagan_tekshir();

-- ------------------------------------------------------------
-- 6. QARZI BOR BEMORNI RASMAN CHIQARISH
--    Hozir qarz bo'lsa chiqarib bo'lmaydi. Amalda bemor baribir
--    ketadi — natijada u tizimda abadiy "yotibdi" bo'lib qoladi
--    va ovqat hisobiga qo'shilaveradi. Bu aynan tizim hal qilishi
--    kerak bo'lgan muammoning qaytishi.
-- ------------------------------------------------------------
-- DIQQAT: mijoz qarori bo'yicha 09_narx_va_telefon.sql da qarz bilan
-- chiqarish BUTUNLAY bekor qilingan (buxgalter chek beradi -> qorovul
-- chekni ko'rib chiqaradi). 09 ishga tushgan bazada bu funksiyani
-- tiklab qo'ymaymiz — aks holda taqiq teshilib qoladi.
DO $blok6$
BEGIN
IF migratsiya_bosqichi() >= 9 THEN
  RAISE NOTICE '09 ishga tushgan — qarz bilan chiqarish tiklanmaydi, trg_qarz_tekshir() ham o''zgarmaydi.';
  RETURN;
END IF;
EXECUTE $f$
CREATE OR REPLACE FUNCTION bemor_chiqar_qarz_bilan(
  p_yotqizish int, p_sabab text, p_vaqt timestamptz DEFAULT now()
) RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_qarz numeric;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[],
                        'qarz bilan chiqarish');
  IF coalesce(trim(p_sabab), '') = '' THEN
    RAISE EXCEPTION 'Qarz bilan chiqarish uchun sabab yozilishi shart.';
  END IF;

  v_qarz := qarz(p_yotqizish);

  UPDATE yotqizishlar
     SET haqiqiy_chiqish = p_vaqt,
         holat = 'chiqdi',
         izoh = coalesce(izoh || ' | ', '') ||
                format('QARZ BILAN CHIQARILDI: %s soʻm. Sabab: %s. Kim: %s',
                       to_char(v_qarz, 'FM999G999G999'), p_sabab, joriy_fish())
   WHERE id = p_yotqizish AND holat = 'yotmoqda';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi yoki bemor allaqachon chiqarilgan.';
  END IF;
  RETURN v_qarz;
END $$
$f$;

-- Trigger endi holat allaqachon 'chiqdi' qilib qo'yilgan holatni o'tkazadi
EXECUTE $f$
CREATE OR REPLACE FUNCTION trg_qarz_tekshir() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_qarz numeric;
BEGIN
  IF NEW.haqiqiy_chiqish IS NOT NULL AND OLD.haqiqiy_chiqish IS NULL THEN
    IF NEW.holat = 'chiqdi' AND OLD.holat = 'yotmoqda'
       AND NEW.izoh IS DISTINCT FROM OLD.izoh
       AND NEW.izoh LIKE '%QARZ BILAN CHIQARILDI%' THEN
      RETURN NEW;                      -- super_admin ruxsati bilan
    END IF;
    SELECT GREATEST(0, NEW.summa + NEW.xona_summa - tolangan(NEW.id)) INTO v_qarz;
    IF v_qarz > 0 THEN
      RAISE EXCEPTION 'Bemorni chiqarish mumkin emas. To''lanmagan qarzdorlik mavjud: % so''m.',
        to_char(v_qarz, 'FM999G999G999')
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.holat := 'chiqdi';
  END IF;
  RETURN NEW;
END $$
$f$;
END $blok6$;

-- ------------------------------------------------------------
-- 7. Administrator oldindan to'lovni qabul qila olsin
--    (qabulxonada pulni administrator oladi — hozir tranzaksiya
--     butunlay rad etilardi va bemor ham ro'yxatga tushmasdi)
-- ------------------------------------------------------------
-- DIQQAT: yangi parametr qo'shilgani uchun eski imzoni o'chirish SHART.
-- Aks holda ikkita bir xil nomli funksiya qoladi va PostgREST
-- "function is not unique" xatosini beradi.
-- DIQQAT: bu funksiya keyinchalik 09 va 11 fayllarida qayta yozilgan
-- (xona puli faqat mustaqil bemordan olinadi, narx xona TURIga bog'langan).
-- Ular ishga tushgan bazada eski variantni tiklamaymiz.
-- bemor_qidir() ham 09 da "hamroh" ustuni bilan qayta yozilgan —
-- uni CREATE OR REPLACE bilan o'zgartirish mumkin emas (42P13).
DO $blok7$
BEGIN
IF migratsiya_bosqichi() >= 9 THEN
  RAISE NOTICE '09 ishga tushgan — bemor_joylashtir() va bemor_qidir() o''zgartirilmaydi.';
  RETURN;
END IF;

EXECUTE $f$
DROP FUNCTION IF EXISTS bemor_joylashtir(
  text, text, jins_turi, text, int, boolean, shaxs_roli,
  int, date, date, numeric, int)
$f$;

EXECUTE $f$
CREATE OR REPLACE FUNCTION bemor_joylashtir(
  p_familiya text, p_ism text, p_jins jins_turi, p_telefon text,
  p_yosh int, p_chet_el boolean, p_roli shaxs_roli,
  p_koyka int, p_kirish date, p_reja_chiqish date,
  p_oldindan numeric DEFAULT 0, p_asosiy int DEFAULT NULL,
  p_bemor_id int DEFAULT NULL          -- qayta kelgan bemor uchun
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_bemor int; v_yotqizish int; v_summa numeric; v_xona_summa numeric := 0;
  v_xona int; v_band int;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin','administrator']::rol_turi[],
                        'bemorni ro''yxatga olish');

  IF p_bemor_id IS NOT NULL THEN
    SELECT id INTO v_bemor FROM bemorlar WHERE id = p_bemor_id;
    IF v_bemor IS NULL THEN
      RAISE EXCEPTION 'Bemor topilmadi (id: %).', p_bemor_id;
    END IF;
  ELSE
    INSERT INTO bemorlar (familiya, ism, jins, telefon, yosh, chet_el, fuqaroligi)
    VALUES (p_familiya, p_ism, p_jins, p_telefon, p_yosh, p_chet_el,
            CASE WHEN p_chet_el THEN 'Chet el fuqarosi' ELSE 'O''zbekiston' END)
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

-- Telefon bo'yicha mavjud bemorni topish (qabulda dublikatni oldini olish)
EXECUTE $f$
CREATE OR REPLACE FUNCTION bemor_qidir(p_matn text)
RETURNS TABLE (id int, fish text, telefon text, jins jins_turi,
               yosh int, oxirgi_tashrif date)
LANGUAGE sql STABLE AS $$
  SELECT b.id, b.familiya || ' ' || b.ism, b.telefon, b.jins,
         bemor_yoshi(b), max(y.kirish_sana)
  FROM bemorlar b LEFT JOIN yotqizishlar y ON y.bemor_id = b.id
  WHERE b.telefon ILIKE '%' || p_matn || '%'
     OR (b.familiya || ' ' || b.ism) ILIKE '%' || p_matn || '%'
  GROUP BY b.id
  ORDER BY max(y.kirish_sana) DESC NULLS LAST
  LIMIT 20;
$$
$f$;
END $blok7$;

-- ------------------------------------------------------------
-- 8. ANON ROLINI YOPISH — fayl oxirida, barcha obyektlar
--    yaratilgandan KEYIN. Aks holda yuqorida yaratilgan yangi
--    view'lar standart huquqlar tufayli anon ga ochiq qoladi.
--
--    Bu tizimda login qilmagan foydalanuvchi uchun ochiq
--    ma'lumot yo'q — shuning uchun anon butunlay yopiladi.
--    (Supabase login/parol oqimi auth sxemasi orqali ketadi,
--     unga ta'sir qilmaydi.)
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    -- kelajakda yaratiladigan obyektlar ham anon ga berilmasin
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon';
    EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon';
    -- hozir mavjudlari
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon';
  END IF;
END $$;

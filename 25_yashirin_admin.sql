-- ============================================================
--  25_yashirin_admin.sql — "ADMIN" ROLI VA YASHIRIN EGA HISOBI
--  01, 03, 05, 06, 08..24 dan KEYIN. Idempotent.
--
--  NIMA QILINADI
--    1. Eng yuqori rol endi hamma joyda "Admin" deb ko'rinadi.
--       Bazadagi nomi o'zgarmaydi (super_admin) — shunda eski
--       fayllar, funksiyalar va huquqlar joyida qoladi.
--
--    2. Xodimlar jadvaliga "yashirin" belgisi qo'shiladi.
--       Yashirin xodim:
--         · xodimlar ro'yxatida ko'rinmaydi;
--         · uni boshqa hech kim tahrirlay, o'chira, parolini
--           almashtira olmaydi;
--         · uning borligini ilova hech qayerda bildirmaydi.
--       Yashirin xodim esa hammani ko'radi — shu jumladan
--       o'zi kabi yashirinlarni.
--
--  NEGA KERAK
--    Tizim egasi (siz) uchun alohida hisob qoladi. Mijozning
--    admini xuddi shu huquqlar bilan ishlaydi, lekin sizning
--    hisobingiz uning ro'yxatida umuman ko'rinmaydi.
--
--  HIMOYA QAYERDA
--    Faqat ilovada emas — bazada:
--      · RLS siyosati yashirin qatorni SELECT dan chiqarib
--        tashlaydi (PostgREST orqali ham ko'rinmaydi);
--      · trigger yashirin qatorni UPDATE/DELETE dan himoya
--        qiladi — xodim_tahrir(), xodim_parol(), xodim_telefon()
--        kabi funksiyalar ham undan o'ta olmaydi.
--
--  O'ZINGIZNI QANDAY YASHIRASIZ
--    Ilovada: Sozlamalar -> Xodimlar -> o'z profilingiz ->
--    "Roʻyxatda koʻrinmasin". Bu tugma faqat yashirin
--    xodimlarga va birinchi marta — har qanday adminga
--    ko'rinadi (keyin faqat yashirinlarga).
--    Yoki shu yerda, SQL orqali:
--      SELECT xodim_yashir(<id>, true);
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='qaytarish_ornatildi') THEN
    RAISE EXCEPTION 'Avval 24_qaytarish.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 0. BELGI FUNKSIYASI
--    17_xodimlar.sql qayta ishga tushirilsa, shu fayldagi
--    v_xodimlar ko'rinishini bosib ketmasin.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yashirin_ornatildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- 1. BELGI USTUNI
-- ------------------------------------------------------------
ALTER TABLE xodimlar ADD COLUMN IF NOT EXISTS yashirin boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN xodimlar.yashirin IS
  'Ro''yxatda ko''rinmaydigan hisob (tizim egasi). Faqat yashirin xodim ko''radi.';

-- ------------------------------------------------------------
-- 2. "MEN YASHIRINMANMI?"
--    SECURITY DEFINER — chunki RLS siyosatining o'zi shu
--    funksiyaga tayanadi, aks holda aylanma bog'liqlik bo'lardi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION men_yashirinmi() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid; v_y boolean;
BEGIN
  BEGIN EXECUTE 'SELECT auth.uid()' INTO v_uid;
  EXCEPTION WHEN OTHERS THEN v_uid := NULL; END;

  IF v_uid IS NULL THEN RETURN false; END IF;

  SELECT x.yashirin INTO v_y FROM xodimlar x WHERE x.auth_id = v_uid;
  RETURN COALESCE(v_y, false);
END $$;

-- ------------------------------------------------------------
-- 3. YASHIRIN QATORNI HIMOYA QILISH
--    RLS o'qishni yopadi, bu trigger esa yozishni. Barcha
--    funksiyalar (ular SECURITY DEFINER bo'lsa ham) shu
--    triggerdan o'tadi.
--
--    joriy_rol() NULL bo'lsa — bu ilova emas, Supabase SQL
--    Editor yoki service_role. Unga to'sqinlik qilmaymiz,
--    aks holda egasi o'z hisobini tuzata olmay qoladi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_yashirin_himoya() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  IF COALESCE(OLD.yashirin, false)
     AND joriy_rol() IS NOT NULL
     AND NOT men_yashirinmi()
     AND COALESCE(current_setting('app.yashirin_ruxsat', true), '') <> 'ha' THEN
    -- Ataylab "topilmadi" deymiz: bu hisob borligi bilinmasin.
    RAISE EXCEPTION 'Xodim topilmadi (id %).', OLD.id USING ERRCODE = 'no_data_found';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;

DROP TRIGGER IF EXISTS yashirin_himoya ON xodimlar;
CREATE TRIGGER yashirin_himoya
  BEFORE UPDATE OR DELETE ON xodimlar
  FOR EACH ROW EXECUTE FUNCTION trg_yashirin_himoya();

-- ------------------------------------------------------------
-- 4. RLS — YASHIRIN QATOR KO'RINMASIN
--    Eski "korish" va "sa_xodim" siyosatlari hamma qatorni
--    ochiq qo'yardi. Ikkalasiga ham shart qo'shamiz.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS korish ON xodimlar;
CREATE POLICY korish ON xodimlar FOR SELECT
  USING (joriy_rol() IS NOT NULL AND (NOT yashirin OR men_yashirinmi()));

DROP POLICY IF EXISTS sa_xodim ON xodimlar;
CREATE POLICY sa_xodim ON xodimlar FOR ALL
  USING (joriy_rol() = 'super_admin'::rol_turi AND (NOT yashirin OR men_yashirinmi()))
  WITH CHECK (joriy_rol() = 'super_admin'::rol_turi);

-- "ozini_korish" tegilmaydi: har kim o'z qatorini ko'radi.

-- ------------------------------------------------------------
-- 5. RO'YXAT KO'RINISHI
--    · rol_matn: "Super admin" emas, "Admin";
--    · yashirin ustuni qo'shildi (ilovadagi belgisi uchun);
--    · yashirin qatorlar RLS orqali allaqachon chiqib ketadi.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_xodimlar
WITH (security_invoker = on) AS
SELECT
  x.id,
  x.familiya,
  x.ism,
  x.fish,
  x.telefon,
  tel_raqam(x.telefon)                    AS login_raqam,
  x.rol,
  CASE x.rol
    WHEN 'super_admin'   THEN 'Admin'
    WHEN 'administrator' THEN 'Registrator'
    WHEN 'buxgalter'     THEN 'Buxgalter'
    ELSE 'Kuzatuvchi'
  END                                     AS rol_matn,
  x.faol,
  x.auth_id IS NOT NULL                   AS kira_oladi,
  x.yaratilgan,
  -- yangi ustun oxirida turishi shart: CREATE OR REPLACE VIEW
  -- mavjud ustunlar tartibini o'zgartirishga ruxsat bermaydi
  x.yashirin
FROM xodimlar x
ORDER BY x.faol DESC, x.rol, x.familiya, x.ism;

-- ------------------------------------------------------------
-- 6. YASHIRISH / OCHISH
--    Kim chaqira oladi:
--      · yashirin admin — istalgan vaqtda;
--      · oddiy admin — FAQAT hali birorta yashirin xodim
--        bo'lmaganda (ya'ni birinchi marta, tizim egasi
--        o'zini yashirayotganda).
--    Shu qoida tufayli mijozning admini keyinchalik sizning
--    hisobingizni ochib ham, yashirib ham qo'ya olmaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS xodim_yashir(int, boolean);

CREATE FUNCTION xodim_yashir(p_id int, p_yashirin boolean DEFAULT true)
RETURNS TABLE (id int, fish text, yashirin boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_bor boolean;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'hisobni yashirish');

  SELECT EXISTS (SELECT 1 FROM xodimlar x WHERE x.yashirin) INTO v_bor;

  IF v_bor AND NOT men_yashirinmi() THEN
    RAISE EXCEPTION 'Bu amalni bajara olmaysiz.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM xodimlar x WHERE x.id = p_id) THEN
    RAISE EXCEPTION 'Xodim topilmadi (id %).', p_id USING ERRCODE = 'no_data_found';
  END IF;

  -- o'zgartirish uchun himoyani shu tranzaksiyada ochamiz
  PERFORM set_config('app.yashirin_ruxsat', 'ha', true);
  UPDATE xodimlar x SET yashirin = COALESCE(p_yashirin, true) WHERE x.id = p_id;
  PERFORM set_config('app.yashirin_ruxsat', '', true);

  RETURN QUERY SELECT x.id, x.fish, x.yashirin FROM xodimlar x WHERE x.id = p_id;
END $$;

-- ------------------------------------------------------------
-- 6a. YASHIRIN HISOB BORMI?
--     Ilova shu savolga qarab "Roʻyxatda koʻrinmasin" belgisini
--     ko'rsatadi: yashirin hisob allaqachon bor bo'lsa, uni
--     faqat o'sha yashirin odam ko'radi. Javob — shunchaki "ha"
--     yoki "yo'q": kim ekani, nechtaligi aytilmaydi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yashirin_bormi() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[], 'sozlamalarni koʻrish');
  RETURN EXISTS (SELECT 1 FROM xodimlar x WHERE x.yashirin);
END $$;

-- ------------------------------------------------------------
-- 6b. PAROL VA LOGIN FUNKSIYALARINI HAM YOPAMIZ
--     xodim_parol() va xodim_telefon() xodimlar jadvalini emas,
--     auth.users ni o'zgartiradi — demak 3-banddagi trigger ular
--     uchun ishlamaydi. Shuning uchun ikkalasiga tekshiruv
--     QO'SHAMIZ. Funksiya tanasi qayta yozilmaydi: mavjud matnga
--     huquq tekshiruvidan keyin bitta blok qo'shiladi (18 va 21
--     fayllaridagi usul).
-- ------------------------------------------------------------
--     Bu ish funksiyaga o'ralgan: 22_xodim_login.sql qayta ishga
--     tushirilsa, o'z oxirida shu funksiyani chaqirib tekshiruvni
--     joyiga qaytaradi.
CREATE OR REPLACE FUNCTION yashirin_himoyasini_qosh() RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp AS $patch$
DECLARE
  r        record;
  v_def    text;
  v_qoshim text :=
    E'\n  IF EXISTS (SELECT 1 FROM xodimlar xh WHERE xh.id = p_id AND xh.yashirin)\n'
    '     AND NOT men_yashirinmi() THEN\n'
    '    RAISE EXCEPTION ''Xodim topilmadi (id %).'', p_id USING ERRCODE = ''no_data_found'';\n'
    '  END IF;\n';
BEGIN
  FOR r IN
    SELECT p.oid, p.proname,
           CASE p.proname
             WHEN 'xodim_parol'   THEN '''parolni oʻzgartirish'');'
             ELSE '''loginni oʻzgartirish'');'
           END AS langar
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname IN ('xodim_parol','xodim_telefon')
  LOOP
    v_def := pg_get_functiondef(r.oid);

    IF position('men_yashirinmi()' in v_def) > 0 THEN
      RAISE NOTICE '%(): tekshiruv allaqachon bor.', r.proname;
      CONTINUE;
    END IF;

    IF position(r.langar in v_def) = 0 THEN
      RAISE NOTICE '%(): kutilgan joy topilmadi — tegilmadi.', r.proname;
      CONTINUE;
    END IF;

    EXECUTE replace(v_def, r.langar, r.langar || v_qoshim);
    RAISE NOTICE '%(): yashirin hisob himoyasi qoʻshildi.', r.proname;
  END LOOP;
END $patch$;

SELECT yashirin_himoyasini_qosh();

-- ------------------------------------------------------------
-- 7. anon hech narsaga tegmasin
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 8. TEKSHIRUV
-- ------------------------------------------------------------
SELECT
  CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='xodimlar'
                       AND column_name='yashirin')
       THEN 'toʻgʻri' ELSE 'XATO' END              AS "yashirin ustuni",
  CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                     WHERE tgname='yashirin_himoya' AND NOT tgisinternal)
       THEN 'toʻgʻri' ELSE 'XATO' END              AS "himoya triggeri",
  CASE WHEN EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
                     WHERE c.relname='xodimlar' AND p.polname='korish'
                       AND pg_get_expr(p.polqual, p.polrelid) LIKE '%men_yashirinmi%')
       THEN 'toʻgʻri' ELSE 'XATO' END              AS "RLS yangilandi",
  CASE WHEN (SELECT rol_matn FROM v_xodimlar WHERE rol='super_admin' LIMIT 1) = 'Admin'
         OR NOT EXISTS (SELECT 1 FROM v_xodimlar WHERE rol='super_admin')
       THEN 'toʻgʻri' ELSE 'XATO' END              AS "roli Admin deb koʻrinadi",
  (SELECT count(*) FROM xodimlar WHERE yashirin)   AS "yashirin hisoblar";

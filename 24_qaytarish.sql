-- ============================================================
--  24_qaytarish.sql — ORTIQCHA TO'LOVNI QAYTARISH (VOZVRAT)
--  01, 03, 05, 06, 08..23 dan KEYIN. Idempotent.
--
--  MUAMMO
--    Bemor kelgan kuni butun kurs pulini to'laydi. Uch kundan
--    keyin ketib qolsa, tizim hisobni yotgan kuniga qarab
--    KAMAYTIRADI (trg_qarz_tekshir), lekin to'langan pul joyida
--    qolaveradi. Farq — bemorniki. Shu paytgacha u hech qayerda
--    rasmiylashmasdi: kassadagi pul bilan hisobot bir-biriga
--    to'g'ri kelmay qolardi.
--
--  ENG MUHIM FARQ — OLDINDAN TO'LOV ≠ ORTIQCHA TO'LOV
--    Yotgan bemor butun kursni oldindan to'lagan bo'lsa, bu
--    ORTIQCHA EMAS: u hali kursni yotib o'taydi. hisob() yotgan
--    kunlar bo'yicha o'sib boradi, shuning uchun "to'langan >
--    hisob" holati har bir oldindan to'lovda ko'rinadi. Uni
--    qaytariladigan pul deb hisoblash — xato.
--      ortiqcha()    — faqat CHIQIB KETGAN bemorda. Hisob
--                      muzlagan, farq esa rostdan bemorniki.
--      qaytariladi() — "bugun chiqsa qancha qaytadi" degan
--                      OLDINDAN AYTISH. Chiqarish oynasida
--                      ko'rsatiladi, ogohlantirish emas.
--
--  YECHIM — TO'RT QISM
--    1. ortiqcha() va qaytariladi() — yuqoridagi ikki tushuncha.
--
--    2. tolov_qaytar() — pulni rasman qaytarish. tolovlar
--       jadvaliga MANFIY qator yozadi. Shuning uchun:
--         · tolangan() o'zi kamayadi, qarz/ortiqcha to'g'ri bo'ladi;
--         · kassadagi pul (bugungi tushum) ham kamayadi;
--         · qaytarishning ham tilxati bo'ladi — bemor imzo
--           chekib oladi.
--       Jadvaldagi CHECK (summa <> 0) manfiy qatorga ruxsat beradi.
--       Bemor HALI YOTGAN bo'lsa bu funksiya ishlamaydi — pul
--       chiqarish paytida, 3-banddagi funksiya orqali qaytariladi.
--
--    3. bemor_chiqar_qaytarib() — CHIQARISH VA QAYTARISH BITTA
--       AMALDA. Kassir bitta tugma bosadi: bemor chiqadi, hisob
--       muzlaydi, farq o'sha zahoti qaytariladi va tilxat raqami
--       qaytariladi. Yarim yo'lda uzilib qolmaydi — ikkalasi
--       bitta tranzaksiyada.
--
--    4. Oddiy bemor_chiqar() da TEKSHIRUV. trg_qarz_tekshir()
--       shu paytgacha faqat qarzni tekshirardi. Endi teskarisini
--       ham: bemorga qaytariladigan pul bo'lsa, oddiy chiqarish
--       ishlamaydi — pul bilan birga chiqariladi. Hisob-kitobda
--       "osilib qolgan" pul qolmaydi.
--
--  QAYTARMASLIK KERAK BO'LSA
--    Ba'zida bemor "qolgani sizga" deydi yoki pul boshqa xizmatga
--    o'tkaziladi. Bu holda super admin sababini yozib
--    bemor_chiqar_ortiqcha_bilan() / ortiqcha_hisobga() dan
--    foydalanadi: hisob ortiqcha summaga KO'TARILADI (pul xizmat
--    hisobiga o'tadi), izohga sabab yoziladi. Kassadan pul
--    chiqmagani uchun tushum o'zgarmaydi, "ortiqcha" ro'yxatida
--    ham osilib qolmaydi.
-- ============================================================

-- ------------------------------------------------------------
-- OLDINGI FAYLLAR TEKSHIRUVI
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='mening_profilim') THEN
    RAISE EXCEPTION 'Avval 23_mening_profilim.sql faylini ishga tushiring — bu fayl undan KEYIN ketadi.';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 0. BELGI FUNKSIYASI
--    Oldingi fayllar (10, 15) qayta ishga tushirilsa, shu
--    fayldagi o'zgarishlarni bosib ketmasin. Ular shu
--    funksiyaning borligini tekshiradi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION qaytarish_ornatildi() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT true $$;

-- ------------------------------------------------------------
-- 0b. SUMMANI O'QIY OLADIGAN QILIB YOZISH
--     to_char(...,'FM999G999G999') serverning tiliga qarab vergul
--     qo'yadi ("4,285,714"). Bizda ajratgich — bo'sh joy.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pul_matn(p_summa numeric) RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = public, pg_temp AS $$
  SELECT replace(replace(to_char(COALESCE(p_summa, 0), 'FM999G999G999G999'),
                         ',', ' '), '.', ' ')
$$;

-- ------------------------------------------------------------
-- 1a. BUGUN CHIQSA QANCHA QAYTADI  (oldindan aytish)
--     Yotgan bemorda ham, chiqqanida ham ishlaydi. Yotgan
--     bemorda hisob() bugungi kunga qarab hisoblanadi, chiqarish
--     paytida esa AYNAN shu summa muzlatiladi — shuning uchun bu
--     raqam chiqarish oynasida ko'rsatiladigan haqiqiy raqam.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION qaytariladi(p_yotqizish int) RETURNS numeric
LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT GREATEST(0, tolangan(p_yotqizish) - hisob(p_yotqizish))
$$;

-- ------------------------------------------------------------
-- 1b. QAYTARILISHI KERAK BO'LGAN, HALI QAYTARILMAGAN PUL
--     FAQAT chiqib ketgan bemorda. Yotgan bemorning oldindan
--     to'lagani ortiqcha emas — u kursni yotib o'taydi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION ortiqcha(p_yotqizish int) RETURNS numeric
LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT CASE
    WHEN (SELECT y.haqiqiy_chiqish FROM yotqizishlar y WHERE y.id = p_yotqizish) IS NULL
      THEN 0::numeric
    ELSE GREATEST(0, tolangan(p_yotqizish) - hisob(p_yotqizish))
  END
$$;

-- ------------------------------------------------------------
-- 2. PULNI QAYTARISH
--    Kim: super admin va buxgalter (pulni u qabul qilgan, u
--    qaytaradi). Registrator pulga tegmaydi.
--
--    Bemor hali yotgan bo'lsa bu yerdan qaytarilmaydi: oldindan
--    to'lov qaytariladigan pul emas. U chiqarish paytida,
--    bemor_chiqar_qaytarib() ichidan qaytariladi (o'sha payt
--    bemor allaqachon chiqarilgan bo'ladi).
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS tolov_qaytar(int, numeric, tolov_usuli, text);

CREATE FUNCTION tolov_qaytar(
  p_yotqizish int,
  p_summa     numeric,
  p_usuli     tolov_usuli DEFAULT 'naqd',
  p_izoh      text DEFAULT NULL
) RETURNS TABLE (
  tolov_id        int,
  qaytarildi      numeric,
  qolgan_ortiqcha numeric,
  chek_raqam      text
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_id       int;
  v_ortiqcha numeric;
  v_chiqdi   timestamptz;
  v_bor      boolean;
BEGIN
  PERFORM huquq_tekshir(
    ARRAY['super_admin','buxgalter']::rol_turi[],
    'pul qaytarish');

  SELECT true, y.haqiqiy_chiqish INTO v_bor, v_chiqdi
    FROM yotqizishlar y WHERE y.id = p_yotqizish;

  IF NOT COALESCE(v_bor, false) THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;

  IF p_summa IS NULL OR p_summa <= 0 THEN
    RAISE EXCEPTION 'Qaytariladigan summa noldan katta boʻlishi kerak.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_chiqdi IS NULL THEN
    RAISE EXCEPTION 'Bemor hali yotibdi — oldindan toʻlangan pul ortiqcha hisoblanmaydi. Pul chiqarish paytida qaytariladi (“Chiqarish va pulni qaytarish”).'
      USING ERRCODE = 'check_violation';
  END IF;

  v_ortiqcha := ortiqcha(p_yotqizish);

  IF v_ortiqcha <= 0 THEN
    RAISE EXCEPTION 'Bu bemorda ortiqcha toʻlov yoʻq — qaytariladigan pul topilmadi.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_summa > v_ortiqcha THEN
    RAISE EXCEPTION 'Koʻpi bilan % soʻm qaytarish mumkin (hisobdan ortiq toʻlangan pul shuncha).',
      pul_matn(v_ortiqcha)
      USING ERRCODE = 'check_violation';
  END IF;

  -- MANFIY qator: kassadan chiqqan pul
  INSERT INTO tolovlar (yotqizish_id, summa, usuli, kim, izoh)
  VALUES (p_yotqizish, -p_summa, p_usuli, joriy_fish(),
          'QAYTARILDI' ||
          COALESCE(': ' || NULLIF(btrim(p_izoh), ''), ': ortiqcha toʻlov'))
  RETURNING id INTO v_id;

  RETURN QUERY
  SELECT v_id, p_summa, ortiqcha(p_yotqizish), 'CHK-' || lpad(v_id::text, 6, '0');
END $$;

-- ------------------------------------------------------------
-- 3. CHIQARISHDA TEKSHIRUV
--    Eski vazifasi saqlanadi (qarz bilan chiqarib bo'lmaydi),
--    ustiga ortiqcha to'lov tekshiruvi qo'shiladi.
--
--    app.ortiqcha_ruxsat — faqat bitta tranzaksiya ichida
--    yashaydigan kalit. Uni pulni birga qaytaradigan funksiyalar
--    qo'yadi; ilova ham, PostgREST ham tashqaridan qo'ya olmaydi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_qarz_tekshir() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_qarz numeric; v_kurs numeric; v_kun int; v_ulush numeric; v_jami numeric;
  v_ortiqcha numeric;
BEGIN
  IF NEW.haqiqiy_chiqish IS NOT NULL AND OLD.haqiqiy_chiqish IS NULL THEN

    IF NEW.koyka_id IS NULL THEN
      -- xonasiz yozuv: pul hisoblanmaydi
      NEW.summa := 0;
      NEW.xona_summa := 0;
    ELSE
      SELECT qiymat INTO v_kurs FROM tariflar WHERE kalit = 'kurs_kun';
      v_kun := GREATEST(1,
        (NEW.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date - NEW.kirish_sana + 1);

      IF v_kurs IS NOT NULL AND v_kurs > 0 AND v_kun < v_kurs THEN
        -- Jami summa hisob() bilan AYNAN bir xil yaxlitlanadi, aks holda
        -- 1 so'mlik farq bemorni chiqara olmay qoldiradi.
        v_ulush := v_kun::numeric / v_kurs;
        v_jami  := round((COALESCE(NEW.summa,0) + COALESCE(NEW.xona_summa,0)) * v_ulush);
        NEW.xona_summa := round(COALESCE(NEW.xona_summa,0) * v_ulush);
        NEW.summa      := v_jami - NEW.xona_summa;
        NEW.izoh := COALESCE(NEW.izoh || ' | ', '') ||
          format('Kunlik hisob: %s kun / %s kunlik kurs', v_kun, v_kurs::int);
      END IF;
    END IF;

    v_qarz := GREATEST(0, NEW.summa + NEW.xona_summa - tolangan(NEW.id));
    IF v_qarz > 0 THEN
      RAISE EXCEPTION 'Bemorni chiqarish mumkin emas. Toʻlanmagan qarzdorlik: % soʻm. Avval buxgalterdan chek olinadi.',
        pul_matn(v_qarz)
        USING ERRCODE = 'check_violation';
    END IF;

    -- YANGI: teskari holat — bemor hisobdan ortiq toʻlagan.
    -- Erta ketgani uchun hisob kamaydi, farq bemorniki. Bu yerdan
    -- faqat pulni birga qaytaradigan funksiya o'tadi.
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
-- 4. CHIQARISH VA PULNI QAYTARISH — BITTA AMALDA
--    Kassir bitta tugma bosadi. Ichida:
--      · bemor chiqariladi (hisob muzlaydi, kamayadi);
--      · ortiqcha pul o'sha zahoti qaytariladi;
--      · tilxat raqami qaytariladi — ilova uni chop etadi.
--    Ikkalasi bitta tranzaksiyada: biri bo'lib, ikkinchisi
--    bo'lmay qolmaydi.
--
--    Ortiqcha pul bo'lmasa oddiy chiqarish kabi ishlaydi —
--    shuning uchun ilova doim shu funksiyani chaqirsa ham bo'ladi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bemor_chiqar_qaytarib(int, tolov_usuli, text, timestamptz);

CREATE FUNCTION bemor_chiqar_qaytarib(
  p_yotqizish int,
  p_usuli     tolov_usuli DEFAULT 'naqd',
  p_izoh      text DEFAULT NULL,
  p_vaqt      timestamptz DEFAULT now()
) RETURNS TABLE (
  qaytarildi     numeric,   -- bemorga berilgan pul (0 bo'lishi mumkin)
  tolov_id       int,       -- manfiy qator (tilxatni chop etish uchun)
  chek_raqam     text,      -- tilxat raqami (qaytarilgan bo'lsa)
  yakuniy_hisob  numeric,
  jami_tolangan  numeric
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_sum  numeric;
  v_id   int;
  v_chek text;
BEGIN
  PERFORM huquq_tekshir(
    ARRAY['super_admin','buxgalter']::rol_turi[],
    'bemorni chiqarish');

  -- Chiqarish tekshiruvini FAQAT shu tranzaksiya uchun ochamiz:
  -- pul pastda, shu yerning o'zida qaytariladi.
  PERFORM set_config('app.ortiqcha_ruxsat', 'ha', true);

  UPDATE yotqizishlar SET haqiqiy_chiqish = p_vaqt
   WHERE id = p_yotqizish AND holat = 'yotmoqda';

  IF NOT FOUND THEN
    PERFORM set_config('app.ortiqcha_ruxsat', '', true);
    RAISE EXCEPTION 'Yotqizish topilmadi yoki bemor allaqachon chiqarilgan.'
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM set_config('app.ortiqcha_ruxsat', '', true);

  v_sum := ortiqcha(p_yotqizish);

  IF v_sum > 0 THEN
    SELECT t.tolov_id, t.chek_raqam INTO v_id, v_chek
      FROM tolov_qaytar(p_yotqizish, v_sum, p_usuli,
             COALESCE(NULLIF(btrim(p_izoh), ''),
                      'erta ketdi — chiqarishda qaytarildi')) t;
  END IF;

  RETURN QUERY
    SELECT v_sum, v_id, v_chek, hisob(p_yotqizish), tolangan(p_yotqizish);
END $$;

-- ------------------------------------------------------------
-- 5. ORTIQCHANI XIZMAT HISOBIGA O'TKAZISH (pul qaytarilmaydi)
--    Chiqib ketgan bemor uchun. Hisob ko'tariladi, izohga sabab
--    yoziladi, kassaga tegilmaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS ortiqcha_hisobga(int, text);

CREATE FUNCTION ortiqcha_hisobga(p_yotqizish int, p_sabab text)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_ortiqcha numeric; v_chiqdi timestamptz;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[],
                        'ortiqcha toʻlovni xizmat hisobiga oʻtkazish');

  IF COALESCE(btrim(p_sabab), '') = '' THEN
    RAISE EXCEPTION 'Sabab yozilishi shart — pul bemorga qaytarilmayapti.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT haqiqiy_chiqish INTO v_chiqdi FROM yotqizishlar WHERE id = p_yotqizish;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yotqizish topilmadi.' USING ERRCODE = 'check_violation';
  END IF;
  IF v_chiqdi IS NULL THEN
    RAISE EXCEPTION 'Bemor hali chiqarilmagan — hisob yakunlanmagan.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_ortiqcha := ortiqcha(p_yotqizish);
  IF v_ortiqcha <= 0 THEN
    RAISE EXCEPTION 'Bu bemorda ortiqcha toʻlov yoʻq.' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE yotqizishlar
     SET summa = COALESCE(summa, 0) + v_ortiqcha,
         izoh  = COALESCE(izoh || ' | ', '') ||
                 format('ORTIQCHA TOʻLOV QAYTARILMADI: %s soʻm xizmat hisobiga oʻtkazildi. Sabab: %s. Kim: %s',
                        pul_matn(v_ortiqcha), btrim(p_sabab), joriy_fish())
   WHERE id = p_yotqizish;

  RETURN v_ortiqcha;
END $$;

-- ------------------------------------------------------------
-- 6. QAYTARMASDAN CHIQARISH (faqat super admin)
--    Chiqarish + 5-banddagi o'tkazma bitta amalda.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS bemor_chiqar_ortiqcha_bilan(int, text, timestamptz);

CREATE FUNCTION bemor_chiqar_ortiqcha_bilan(
  p_yotqizish int, p_sabab text, p_vaqt timestamptz DEFAULT now()
) RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE v_ortiqcha numeric;
BEGIN
  PERFORM huquq_tekshir(ARRAY['super_admin']::rol_turi[],
                        'ortiqcha toʻlovni qaytarmasdan chiqarish');

  IF COALESCE(btrim(p_sabab), '') = '' THEN
    RAISE EXCEPTION 'Sabab yozilishi shart — pul bemorga qaytarilmayapti.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- tekshiruvni shu tranzaksiya uchun ochamiz
  PERFORM set_config('app.ortiqcha_ruxsat', 'ha', true);

  UPDATE yotqizishlar SET haqiqiy_chiqish = p_vaqt
   WHERE id = p_yotqizish AND holat = 'yotmoqda';

  IF NOT FOUND THEN
    PERFORM set_config('app.ortiqcha_ruxsat', '', true);
    RAISE EXCEPTION 'Yotqizish topilmadi yoki bemor allaqachon chiqarilgan.'
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM set_config('app.ortiqcha_ruxsat', '', true);

  v_ortiqcha := ortiqcha(p_yotqizish);
  IF v_ortiqcha > 0 THEN
    UPDATE yotqizishlar
       SET summa = COALESCE(summa, 0) + v_ortiqcha,
           izoh  = COALESCE(izoh || ' | ', '') ||
                   format('ORTIQCHA TOʻLOV QAYTARILMADI: %s soʻm xizmat hisobiga oʻtkazildi. Sabab: %s. Kim: %s',
                          pul_matn(v_ortiqcha), btrim(p_sabab), joriy_fish())
     WHERE id = p_yotqizish;
  END IF;

  RETURN v_ortiqcha;
END $$;

-- ------------------------------------------------------------
-- 7. XULOSA HISOBOTI — QAYTARISHNI ALOHIDA KO'RSATADI
--    Tushum endi faqat KIRIM (musbat to'lovlar). Qaytarilgan pul
--    alohida ustunda turadi, sof tushum = tushum - qaytarilgan.
--    Ortiqcha esa faqat CHIQIB KETGAN bemorlarda sanaladi —
--    buni endi ortiqcha() funksiyasining o'zi ta'minlaydi.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS hisobot_xulosa(date, date);

CREATE FUNCTION hisobot_xulosa(p_dan date, p_gacha date)
RETURNS TABLE (
  tushum        numeric,   -- oraliqdagi kirim (qaytarishsiz)
  naqd          numeric,
  karta         numeric,
  otkazma       numeric,
  tolov_soni    bigint,
  yangi_bemor   bigint,    -- oraliqda kelganlar
  chiqqan       bigint,    -- oraliqda ketganlar
  ortacha_kun   numeric,   -- chiqqanlarning o'rtacha yotgan kuni
  hozir_yotibdi bigint,
  qarz_jami     numeric,
  qarzdor_soni  bigint,
  bron_kutilyapti bigint,
  ortiqcha_jami numeric,   -- chiqqan bemorlarda qaytarilmagan pul
  ortiqcha_soni bigint,
  qaytarilgan   numeric,   -- oraliqda bemorlarga qaytarilgan pul
  qaytarish_soni bigint
) LANGUAGE sql STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    (SELECT COALESCE(sum(summa) FILTER (WHERE summa > 0), 0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha),
    (SELECT COALESCE(sum(summa) FILTER (WHERE summa > 0), 0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha AND usuli='naqd'),
    (SELECT COALESCE(sum(summa) FILTER (WHERE summa > 0), 0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha AND usuli='karta'),
    (SELECT COALESCE(sum(summa) FILTER (WHERE summa > 0), 0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha AND usuli='otkazma'),
    (SELECT count(*) FILTER (WHERE summa > 0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha),
    (SELECT count(*) FROM yotqizishlar
      WHERE kirish_sana BETWEEN p_dan AND p_gacha AND holat <> 'bekor'),
    (SELECT count(*) FROM yotqizishlar
      WHERE (haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
            BETWEEN p_dan AND p_gacha),
    (SELECT round(AVG((haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
                      - kirish_sana + 1), 1)
       FROM yotqizishlar
      WHERE (haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date
            BETWEEN p_dan AND p_gacha),
    (SELECT count(*) FROM yotqizishlar WHERE holat='yotmoqda'),
    (SELECT COALESCE(sum(qarz),0) FROM v_qarzdorlar),
    (SELECT count(*) FROM v_qarzdorlar),
    (SELECT count(*) FROM bronlar WHERE holat='kutilmoqda'),
    -- Bemor erta ketsa hisob kamayadi, lekin to'langan pul joyida
    -- qoladi — farq qaytarilishi kerak. ortiqcha() yotgan bemorda
    -- doim 0, shuning uchun bu yerda faqat chiqqanlar sanaladi.
    (SELECT COALESCE(sum(ortiqcha(y.id)), 0) FROM yotqizishlar y
      WHERE y.holat <> 'bekor'),
    (SELECT count(*) FROM yotqizishlar y
      WHERE y.holat <> 'bekor' AND ortiqcha(y.id) > 0),
    (SELECT COALESCE(-sum(summa) FILTER (WHERE summa < 0), 0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha),
    (SELECT count(*) FILTER (WHERE summa < 0) FROM tolovlar
      WHERE sana BETWEEN p_dan AND p_gacha);
$$;

-- ------------------------------------------------------------
-- 8. BEMORLAR HISOBOTI — "ortiqcha" ustuni
--    Yotgan bemorning oldindan to'lovi ortiqcha deb sanalmasin.
--    Funksiya tanasi qayta yozilmaydi: 16_tashxis.sql qo'shgan
--    "tashxis" ustuni joyida qolishi uchun mavjud matnning faqat
--    shu ifodasi ortiqcha() chaqiruviga almashtiriladi.
-- ------------------------------------------------------------
DO $$
DECLARE
  v_def  text;
  v_eski text := 'GREATEST(0, tolangan(y.id) - hisob(y.id))';
  v_yangi text := 'ortiqcha(y.id)';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'hisobot_bemorlar';

  IF v_def IS NULL THEN
    RAISE NOTICE 'hisobot_bemorlar() topilmadi — oʻtkazib yuborildi.';
    RETURN;
  END IF;

  -- eski variant ham, shu faylning oldingi tahriri ham to'g'rilanadi
  v_def := replace(v_def,
    'CASE WHEN y.haqiqiy_chiqish IS NULL THEN 0::numeric'
    || ' ELSE GREATEST(0, tolangan(y.id) - hisob(y.id)) END', v_yangi);

  IF position(v_eski in v_def) = 0 AND position(v_yangi in v_def) = 0 THEN
    RAISE NOTICE 'hisobot_bemorlar() ichida kutilgan ifoda topilmadi — tegilmadi.';
    RETURN;
  END IF;

  EXECUTE replace(v_def, v_eski, v_yangi);
  RAISE NOTICE 'hisobot_bemorlar(): ortiqcha faqat chiqqan bemorlarda sanaydigan boʻldi.';
END $$;

-- ------------------------------------------------------------
-- 9. anon hech narsaga tegmasin
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon';
    EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 10. TEKSHIRUV
-- ------------------------------------------------------------
SELECT
  CASE WHEN (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public'
                AND p.proname IN ('ortiqcha','qaytariladi','tolov_qaytar',
                                  'bemor_chiqar_qaytarib','ortiqcha_hisobga',
                                  'bemor_chiqar_ortiqcha_bilan')) = 6
       THEN 'toʻgʻri' ELSE 'XATO' END                       AS "6 ta yangi funksiya",
  CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='public' AND p.proname='trg_qarz_tekshir'
                       AND pg_get_functiondef(p.oid) LIKE '%qaytarilishi kerak%')
       THEN 'toʻgʻri' ELSE 'XATO' END                       AS "chiqarishda tekshiruv",
  CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='public' AND p.proname='hisobot_xulosa'
                       AND pg_get_function_result(p.oid) LIKE '%qaytarilgan%')
       THEN 'toʻgʻri' ELSE 'XATO' END                       AS "hisobotda qaytarish";

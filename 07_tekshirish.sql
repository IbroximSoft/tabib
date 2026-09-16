-- ============================================================
--  07_tekshirish.sql — tekshiruv fayli.
--  Hech narsani o'zgartirmaydi, faqat o'qiydi.
--  Istalgan bosqichda ishga tushirish mumkin — nima yetishmayotganini
--  aytadi. Hammasi tugagach har bir qatorda "OK" bo'lishi kerak.
--
--  UCHTA JADVAL qaytaradi:
--    1) Qaysi fayl ishga tushgan, qaysisi yo'q
--    2) 20 ta tekshiruv
--    3) Hozirgi holat (bemorlar, ovqat)
-- ============================================================

-- ------------------------------------------------------------
--  1-JADVAL: QAYSI FAYLLAR ISHGA TUSHGAN
--
--  Har bir fayl o'zidan keyin qoladigan iz bo'yicha aniqlanadi.
--  Hammasi tizim kataloglaridan o'qiladi — shuning uchun jadval
--  yoki ustun yo'q bo'lsa ham bu so'rov yiqilmaydi.
-- ------------------------------------------------------------
WITH f(tartib, fayl, bor) AS (
  VALUES
    (6,  '06_tuzatishlar.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='migratsiya_bosqichi')),
    (8,  '08_hamrohlar.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='bemor_qabul')),
    (9,  '09_narx_va_telefon.sql',
         to_regclass('public.narx_tarixi') IS NOT NULL),
    (10, '10_kunlik_hisob.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='v_yotqizishlar'
                    AND column_name='kurs_summa')),
    (11, '11_xona_turlari.sql',
         to_regclass('public.xona_turlari') IS NOT NULL),
    (12, '12_xonalar_korinishi.sql',
         to_regclass('public.v_koykalar') IS NOT NULL),
    (13, '13_chek.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='tolov_qosh' AND p.pronargs=5)),
    (14, '14_bronlar.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='bronlar'
                    AND column_name='yotqizish_id')),
    (15, '15_hisobotlar.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='hisobot_xulosa')),
    (16, '16_tashxis.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='yotqizishlar'
                    AND column_name='tashxis')),
    (17, '17_xodimlar.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='xodim_qosh')),
    (18, '18_buxgalter.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='buxgalter_toraytirildi')),
    (19, '19_bron_bogla.sql',
         EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                  WHERE c.relname='yotqizishlar' AND t.tgname='bron_avto_bogla')),
    (20, '20_bron_xona.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='bron_xona')),
    (21, '21_registrator.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='registrator_toraytirildi')),
    (22, '22_xodim_login.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='xodim_parol')),
    (23, '23_mening_profilim.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='mening_profilim')),
    (24, '24_qaytarish.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='tolov_qaytar')),
    (25, '25_yashirin_admin.sql',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='xodimlar'
                    AND column_name='yashirin')),
    (26, '26_tahrir_ochirish.sql',
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname='public' AND p.proname='bemor_ochir'))
)
SELECT
  fayl AS "fayl",
  CASE WHEN bor THEN 'ISHGA TUSHGAN' ELSE '— yoʻq —' END AS "holati",
  CASE
    WHEN bor THEN ''
    WHEN tartib = (SELECT min(tartib) FROM f WHERE NOT bor)
      THEN '<<< KEYINGI SHU FAYLNI ISHGA TUSHIRING'
    ELSE 'undan keyin'
  END AS "nima qilish kerak"
FROM f ORDER BY tartib;

-- ------------------------------------------------------------
--  2-JADVAL: TEKSHIRUVLAR
-- ------------------------------------------------------------
WITH t AS (

  -- 1. Rekursiya: joriy_rol() endi RLS dan ustunmi?
  SELECT 1 AS n, 'Login rekursiyasi tuzatildimi' AS tekshiruv,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
      WHERE ns.nspname='public' AND p.proname IN ('joriy_rol','joriy_fish')
        AND p.prosecdef) = 2 AS ok,
    'joriy_rol va joriy_fish SECURITY DEFINER bo''lishi kerak' AS izoh

  UNION ALL
  -- 2. View'lar RLS ga bo'ysunadimi?
  SELECT 2, 'View''lar RLS ostidami',
    NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
      WHERE ns.nspname='public' AND c.relkind='v' AND c.relname LIKE 'v\_%'
        AND coalesce((SELECT option_value FROM pg_options_to_table(c.reloptions)
                      WHERE option_name='security_invoker'),'off') <> 'on'),
    'har bir v_ ko''rinishda security_invoker = on'

  UNION ALL
  -- 3. anon (login qilmagan) yopilganmi?
  SELECT 3, 'Anon kalit yopilganmi',
    NOT EXISTS (
      SELECT 1 FROM information_schema.role_table_grants
      WHERE grantee='anon' AND table_schema='public'),
    'anon roliga public sxemada hech qanday huquq qolmasligi kerak'

  UNION ALL
  -- 4. SECURITY DEFINER funksiyalarda search_path
  SELECT 4, 'search_path qulflanganmi',
    NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='public' AND p.prosecdef
        AND (p.proconfig IS NULL OR NOT EXISTS (
             SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))),
    'barcha SECURITY DEFINER funksiyalarda search_path bo''lishi kerak'

  UNION ALL
  -- 5. Xona sig'imi dublikatsiz sanaladimi?
  SELECT 5, 'Xona sig''imi to''g''ri sanaladimi',
    (SELECT pg_get_viewdef('v_xona_holati'::regclass) LIKE '%DISTINCT%'),
    'v_xona_holati count(DISTINCT ...) ishlatishi kerak'

  UNION ALL
  -- 6. Yangi funksiya va ko'rinishlar o'rnatildimi?
  SELECT 6, 'Yangi funksiyalar joyidami',
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='public'
        AND p.proname IN ('ovqat_hisobi','bemor_qidir','bemor_qabul',
                          'qarovchini_bemorga','tarif_ozgartir','xona_turi_narx')) = 6,
    'ovqat_hisobi, bemor_qidir, bemor_qabul, qarovchini_bemorga, tarif_ozgartir, xona_turi_narx'

  UNION ALL
  SELECT 7, 'v_tasdiqlanmagan ko''rinishi bormi',
    to_regclass('public.v_tasdiqlanmagan') IS NOT NULL,
    'muddati o''tgan bemorlar ro''yxati'

  UNION ALL
  -- 8. bemor_joylashtir ikkilanib qolmadimi? (eng xavfli nuqta)
  SELECT 8, 'bemor_joylashtir yagonami',
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='public' AND p.proname='bemor_joylashtir') = 1,
    'ikkita bo''lsa frontend "function is not unique" xatosini beradi'

  UNION ALL
  -- 9. v_umumiy tiklandimi va yangi ustun bormi?
  SELECT 9, 'v_umumiy tiklandimi',
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='v_umumiy'
              AND column_name='tasdiqlanmagan'),
    'Dashboard shu ko''rinishdan o''qiydi'

  UNION ALL
  -- 10. Tasdiqlanmagan bemor koykasini himoya qiluvchi trigger
  SELECT 10, 'Koyka himoyasi qo''yildimi',
    EXISTS (SELECT 1 FROM pg_trigger
            WHERE tgname='tasdiqlanmagan_tekshir' AND NOT tgisinternal),
    'muddati o''tgan bemor koykasiga yangi bemor qo''yilmasin'

  UNION ALL
  -- 11. Telefon takrorlanmasligi (09)
  SELECT 11, 'Telefon raqami takrorlanmaydimi',
    EXISTS (SELECT 1 FROM pg_indexes
            WHERE schemaname='public' AND indexname='bemorlar_telefon_uniq'),
    'asosiy bemorlar uchun unikal indeks bo''lishi kerak'

  UNION ALL
  -- 12. Qarz bilan chiqarish olib tashlandimi (mijoz qarori)
  SELECT 12, 'Qarz bilan chiqarish yopiqmi',
    NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
                WHERE ns.nspname='public' AND p.proname='bemor_chiqar_qarz_bilan'),
    'bu funksiya umuman bo''lmasligi kerak'

  UNION ALL
  -- 13. Narx o'zgarishlari yozib boriladimi
  SELECT 13, 'Narx tarixi saqlanadimi',
    to_regclass('public.narx_tarixi') IS NOT NULL,
    'kim, qachon, qaysi narxni o''zgartirgani yozilsin'

  UNION ALL
  -- 14. Kunlik hisob (10)
  SELECT 14, 'Kunlik hisob ishlayaptimi',
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
            WHERE ns.nspname='public' AND p.proname='hisob'),
    'hisob() — yotgan kunlar bo''yicha summa'

  UNION ALL
  -- 15. Xonasiz bemor qarzdor bo'lmasin
  SELECT 15, 'Xonasiz bemor qarzdor emasmi',
    (SELECT pg_get_viewdef('v_qarzdorlar'::regclass) LIKE '%koyka_id IS NOT NULL%'),
    'v_qarzdorlar faqat xonaga joylashtirilganlarni ko''rsatsin'

  UNION ALL
  -- 16. Xona narxi turga bog'langanmi (11)
  SELECT 16, 'Xona narxi turga bogʻlanganmi',
    to_regclass('public.xona_turlari') IS NOT NULL
    AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='xonalar_turi_fk'),
    'xona_turlari jadvali va xonalar.turi bogʻlanishi bo''lsin'

  UNION ALL
  -- 17. Eski fayl qayta ishga tushib, qoidalarni bekor qilmadimi?
  --     (06 yoki 09 ni qayta ishga tushirish shunga olib kelardi)
  SELECT 17, 'Yangi qoidalar orqaga qaytmadimi',
    (SELECT 'hamroh' = ANY(p.proargnames)
       FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='public' AND p.proname='bemor_qidir')
    AND (SELECT position('xona_narxi' in pg_get_functiondef(p.oid)) > 0
           FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
          WHERE ns.nspname='public' AND p.proname='bemor_joylashtir')
    AND (SELECT position('Kunlik hisob' in pg_get_functiondef(p.oid)) > 0
           FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
          WHERE ns.nspname='public' AND p.proname='trg_qarz_tekshir'),
    'bemor_qidir hamroh qaytarsin, xona narxi turdan olinsin, chiqarishda kunlik hisob ishlasin'

  UNION ALL
  -- 18. Migratsiya bosqichi to'liqmi
  -- DIQQAT: bu yerda migratsiya_bosqichi() ni CHAQIRMAYMIZ.
  -- U 06 da yaratiladi, ya'ni 06 dan oldin bu fayl butunlay
  -- yiqilib qolardi. Tekshiruv fayli hech qachon yiqilmasligi,
  -- aksincha nima yetishmayotganini aytishi kerak.
  SELECT 18, 'Barcha fayllar ishga tushganmi',
    to_regclass('public.v_bronlar') IS NOT NULL
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'hisobot_xulosa')
    AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='yotqizishlar'
                   AND column_name='tashxis')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'xodim_qosh')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'buxgalter_toraytirildi')
    AND EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                 WHERE c.relname = 'yotqizishlar' AND t.tgname = 'bron_avto_bogla')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'bron_xona')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'registrator_toraytirildi')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'xodim_parol')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'mening_profilim')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname = 'tolov_qaytar'),
    '24_qaytarish.sql gacha hammasi ishga tushirilgan bo''lsin'

  UNION ALL
  -- 19. Chek zanjiri butunmi (13)
  SELECT 19, 'Chek chiqarish tayyormi',
    (SELECT 'kunlik' = ANY(p.proargnames)
       FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
      WHERE ns.nspname = 'public' AND p.proname = 'chek')
    AND (SELECT 'chek_raqam' = ANY(p.proargnames)
           FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
          WHERE ns.nspname = 'public' AND p.proname = 'tolov_qosh'),
    'chek() kunlik narxni bersin, tolov_qosh() chek raqamini qaytarsin'

  UNION ALL
  -- 20. Bron qarz yaratmaydimi (14)
  --     Bron yotqizish emas — pul hisobiga umuman tegmasligi kerak.
  SELECT 20, 'Bron qarz yaratmaydimi',
    -- DIQQAT: bronlar.yotqizish_id 14_bronlar.sql da qo'shiladi.
    -- Ustunga to'g'ridan-to'g'ri murojaat qilsak, bu fayl 14 dan
    -- OLDIN ishga tushirilganda butun tekshiruv yiqiladi (42703).
    -- to_jsonb orqali o'qish xavfsiz: ustun yo'q bo'lsa NULL beradi.
    NOT EXISTS (
      SELECT 1 FROM bronlar br
       WHERE br.holat = 'kutilmoqda'
         AND to_jsonb(br) ->> 'yotqizish_id' IS NOT NULL)
    AND (SELECT count(*) FROM v_qarzdorlar q
          WHERE NOT EXISTS (SELECT 1 FROM yotqizishlar y
                             WHERE y.id = q.yotqizish_id AND y.koyka_id IS NOT NULL)) = 0,
    'kutilayotgan bronda yotqizish bo''lmasin, qarzdorlar faqat xonadagi bemorlardan chiqsin'

  UNION ALL
  -- 21. Ortiqcha to'lov qaytarish tizimi o'rnatilganmi (24)
  SELECT 21, 'Ortiqcha to''lov qaytariladimi',
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname='public' AND p.proname='tolov_qaytar')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname='public' AND p.proname='bemor_chiqar_qaytarib')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname='public' AND p.proname='qaytariladi')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname='public' AND p.proname='trg_qarz_tekshir'
                   AND pg_get_functiondef(p.oid) LIKE '%qaytarilishi kerak%')
    AND EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname='public' AND p.proname='hisobot_xulosa'
                   AND pg_get_function_result(p.oid) LIKE '%qaytarilgan%'),
    'chiqarish bilan birga qaytarish (bemor_chiqar_qaytarib) bo''lsin, chiqarishda ortiqcha tekshirilsin, hisobotda qaytarish ko''rinsin'

  UNION ALL
  -- 22. Yashirin ega hisobi (25)
  SELECT 22, 'Yashirin hisob himoyalanganmi',
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='xodimlar'
               AND column_name='yashirin')
    AND EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname='yashirin_himoya' AND NOT tgisinternal)
    AND EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
                 WHERE c.relname='xodimlar' AND p.polname='korish'
                   AND pg_get_expr(p.polqual, p.polrelid) LIKE '%men_yashirinmi%'),
    'yashirin ustuni, himoya triggeri va RLS siyosati o''rnatilgan bo''lsin'

  UNION ALL
  -- 23. Bemorni o'chirish va xonani tahrirlash (26)
  SELECT 23, 'Bemor o''chirish / xona tahriri',
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public'
        AND p.proname IN ('bemor_ochir','xona_tahrir','xona_koyka')) = 3,
    'bemor_ochir(), xona_tahrir() va xona_koyka() bo''lsin'
)
SELECT n AS "№",
       CASE WHEN ok THEN 'OK' ELSE 'XATO' END AS "natija",
       tekshiruv AS "tekshiruv",
       CASE WHEN ok THEN '' ELSE izoh END AS "nima kutilgan"
FROM t ORDER BY n;

-- ------------------------------------------------------------
-- Qo'shimcha: hozirgi holat
--
--   Faqat 01_schema.sql dagi jadvallardan o'qiladi. Avval bu yerda
--   ovqat_hisobi() va v_tasdiqlanmagan ishlatilardi — ular 06 da
--   yaratiladi, ya'ni 06 gacha bu so'rov yiqilardi. Tekshiruv
--   fayli har qanday holatda javob berishi kerak.
-- ------------------------------------------------------------
WITH faol AS (
  SELECT y.kirish_sana,
         COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                  y.reja_chiqish) AS tugash
  FROM yotqizishlar y
  WHERE y.holat <> 'bekor'
    AND y.kirish_sana <= current_date
    AND COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date,
                 y.reja_chiqish) >= current_date
)
SELECT 'Hozir yotmoqda' AS korsatkich,
       (SELECT count(*)::text FROM yotqizishlar WHERE holat = 'yotmoqda') AS qiymat
UNION ALL
SELECT 'Muddati o''tgan, chiqarilmagan',
       (SELECT count(*)::text FROM yotqizishlar
         WHERE holat = 'yotmoqda' AND reja_chiqish < current_date)
UNION ALL
SELECT 'Ovqat porsiyasi bugunga',
       (SELECT (count(*) FILTER (WHERE kirish_sana <> current_date)
                + count(*)
                + count(*) FILTER (WHERE tugash <> current_date))::text
          FROM faol)
UNION ALL
SELECT 'Xonasiz yotgan',
       (SELECT count(*)::text FROM yotqizishlar
         WHERE holat = 'yotmoqda' AND koyka_id IS NULL);

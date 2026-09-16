-- ============================================================
--  05_hisobotlar.sql — Viewer va rahbariyat uchun filtrlash asosi
--  01_schema.sql va 03_rollar.sql dan KEYIN ishga tushiriladi.
-- ============================================================
--  Maqsad: shifoxona boshlig'i hech qanday SQL bilmasdan,
--  frontdagi oddiy filtrlar orqali hamma narsani ko'ra olsin.
--  Front faqat quyidagi ko'rinishlarga filter qo'yadi.
-- ============================================================

-- ------------------------------------------------------------
-- 1. BARCHA YOTQIZISHLAR — asosiy filtrlanadigan ro'yxat
--    Chiqib ketganlar ham shu yerda (tarix yo'qolmaydi).
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_yotqizishlar AS
SELECT
  y.id                         AS yotqizish_id,
  b.id                         AS bemor_id,
  b.familiya, b.ism,
  b.familiya || ' ' || b.ism   AS fish,
  b.jins, b.telefon, b.chet_el, b.fuqaroligi,
  bemor_yoshi(b)               AS yosh,
  y.roli,
  y.holat,
  CASE y.holat
    WHEN 'yotmoqda' THEN 'Yotmoqda'
    WHEN 'chiqdi'   THEN 'Chiqdi'
    ELSE 'Bekor qilingan'
  END                          AS holat_matn,

  bo.id                        AS bolim_id,
  bo.nomi                      AS bolim,
  x.id                         AS xona_id,
  x.raqam                      AS xona,
  k.raqam                      AS koyka,
  (y.koyka_id IS NOT NULL)     AS xonada,

  y.kirish_sana, y.kirish_vaqt, y.reja_chiqish,
  (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date AS haqiqiy_chiqish,
  y.haqiqiy_chiqish            AS haqiqiy_chiqish_vaqt,

  -- Necha kun yotdi: chiqqan bo'lsa haqiqiy, bo'lmasa bugungacha
  (COALESCE((y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date, current_date)
     - y.kirish_sana + 1)      AS yotgan_kun,
  -- Rejadan qancha erta/kech chiqdi (manfiy = erta ketdi)
  CASE WHEN y.haqiqiy_chiqish IS NOT NULL
       THEN (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date - y.reja_chiqish
  END                          AS reja_farqi,

  y.summa                      AS bemor_summa,
  y.xona_summa,
  y.summa + y.xona_summa       AS umumiy,
  tolangan(y.id)               AS tolangan,
  qarz(y.id)                   AS qarz,
  (qarz(y.id) > 0)             AS qarzdor,
  y.band_davri,
  y.izoh
FROM yotqizishlar y
  JOIN bemorlar b       ON b.id = y.bemor_id
  LEFT JOIN koykalar k  ON k.id = y.koyka_id
  LEFT JOIN xonalar x   ON x.id = k.xona_id
  LEFT JOIN bolimlar bo ON bo.id = x.bolim_id;

-- ------------------------------------------------------------
-- 2. BARCHA TO'LOVLAR — kassa filtri
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_tolovlar AS
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
  bo.nomi                    AS bolim,
  y.summa + y.xona_summa     AS umumiy,
  qarz(y.id)                 AS qolgan_qarz
FROM tolovlar t
  JOIN yotqizishlar y   ON y.id = t.yotqizish_id
  JOIN bemorlar b       ON b.id = y.bemor_id
  LEFT JOIN koykalar k  ON k.id = y.koyka_id
  LEFT JOIN xonalar x   ON x.id = k.xona_id
  LEFT JOIN bolimlar bo ON bo.id = x.bolim_id;

-- ------------------------------------------------------------
-- 3. UMUMIY HOLAT — dashboard kartalari (bitta so'rov)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_umumiy AS
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
  (SELECT count(*) FROM v_xona_holati WHERE holat='bosh')               AS bosh_xona,
  (SELECT count(*) FROM v_xona_holati WHERE holat IN ('qisman','toliq'))AS band_xona,
  (SELECT count(*) FROM bronlar WHERE holat='kutilmoqda')               AS bron,
  (SELECT count(*) FROM v_qarzdorlar)                                   AS qarzdor_soni,
  (SELECT COALESCE(sum(qarz),0) FROM v_qarzdorlar)                      AS qarz_jami,
  (SELECT COALESCE(sum(summa),0) FROM tolovlar WHERE sana=current_date) AS bugungi_tushum,
  (SELECT COALESCE(sum(summa),0) FROM tolovlar
     WHERE sana >= date_trunc('month', current_date)::date)             AS oylik_tushum;

-- ------------------------------------------------------------
-- 4. KUNLIK HISOBOT — sana oralig'i bo'yicha
--    Har kun uchun: nechta keldi, ketdi, yotdi, qancha tushum.
--
--    "yotgan" ustuni ovqat hisobi uchun ham ishlatiladi:
--    bemor, farzand va qarovchi — hammasi sanaladi.
--    ⚠ MIJOZDAN SO'RALSIN: qarovchi ovqatlanadimi yoki uning
--    ovqati alohida hisoblanadimi? Agar ajratish kerak bo'lsa,
--    quyidagi qatorga "AND y.roli <> 'qarovchi'" qo'shiladi.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION hisobot_kunlik(p_dan date, p_gacha date)
RETURNS TABLE (
  sana date, keldi bigint, ketdi bigint,
  yotgan bigint, shundan_qarovchi bigint, tushum numeric
) LANGUAGE sql STABLE AS $$
  SELECT
    g::date,
    (SELECT count(*) FROM yotqizishlar y WHERE y.kirish_sana = g::date),
    (SELECT count(*) FROM yotqizishlar y
      WHERE (y.haqiqiy_chiqish AT TIME ZONE 'Asia/Tashkent')::date = g::date),
    (SELECT count(*) FROM yotqizishlar y
      WHERE y.holat <> 'bekor' AND y.band_davri @> g::date),
    (SELECT count(*) FROM yotqizishlar y
      WHERE y.holat <> 'bekor' AND y.band_davri @> g::date
        AND y.roli = 'qarovchi'),
    (SELECT COALESCE(sum(t.summa),0) FROM tolovlar t WHERE t.sana = g::date)
  FROM generate_series(p_dan, p_gacha, interval '1 day') g
  ORDER BY 1;
$$;

-- ------------------------------------------------------------
-- 5. MOLIYAVIY XULOSA — sana oralig'i bo'yicha
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION hisobot_moliya(p_dan date, p_gacha date)
RETURNS TABLE (
  korsatkich text, qiymat numeric
) LANGUAGE sql STABLE AS $$
  SELECT 'Jami tushum', COALESCE(sum(summa),0)
    FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha
  UNION ALL
  SELECT 'Naqd', COALESCE(sum(summa),0)
    FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha AND usuli='naqd'
  UNION ALL
  SELECT 'Karta', COALESCE(sum(summa),0)
    FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha AND usuli='karta'
  UNION ALL
  SELECT 'O''tkazma', COALESCE(sum(summa),0)
    FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha AND usuli='otkazma'
  UNION ALL
  SELECT 'To''lovlar soni', count(*)
    FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha
  UNION ALL
  SELECT 'Yangi bemorlar', count(*)
    FROM yotqizishlar WHERE kirish_sana BETWEEN p_dan AND p_gacha
  UNION ALL
  SELECT 'Joriy qarzdorlik', COALESCE(sum(qarz),0) FROM v_qarzdorlar;
$$;

-- ------------------------------------------------------------
-- 6. KASSIRLAR KESIMI — kim qancha qabul qildi
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION hisobot_kassir(p_dan date, p_gacha date)
RETURNS TABLE (kassir text, tolovlar bigint, jami numeric)
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(kim,'—'), count(*), sum(summa)
  FROM tolovlar WHERE sana BETWEEN p_dan AND p_gacha
  GROUP BY 1 ORDER BY 3 DESC;
$$;

-- ------------------------------------------------------------
-- 7. BO'LIMLAR KESIMI — bandlik va daromad
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_bolim_hisoboti AS
SELECT
  bo.nomi                                             AS bolim,
  count(DISTINCT x.id)                                AS xonalar,
  count(DISTINCT k.id)                                AS koykalar,
  count(DISTINCT y.id) FILTER (WHERE y.holat='yotmoqda') AS band_koyka,
  round(100.0 * count(DISTINCT y.id) FILTER (WHERE y.holat='yotmoqda')
        / NULLIF(count(DISTINCT k.id),0), 1)          AS bandlik_foiz,
  COALESCE(sum(y.summa + y.xona_summa)
           FILTER (WHERE y.holat='yotmoqda'), 0)      AS joriy_summa
FROM bolimlar bo
  LEFT JOIN xonalar x  ON x.bolim_id = bo.id
  LEFT JOIN koykalar k ON k.xona_id = x.id
  LEFT JOIN yotqizishlar y ON y.koyka_id = k.id
GROUP BY bo.id, bo.nomi
ORDER BY bo.tartib;

-- ------------------------------------------------------------
-- 8. Viewer uchun RLS — yangi ko'rinishlar ham ochiq bo'lsin.
--    View'lar asosiy jadvallarning RLS siyosatiga bo'ysunadi,
--    ya'ni faqat faol xodim ko'radi. Qo'shimcha siyosat shart emas.
-- ------------------------------------------------------------

-- Tez qidirish uchun indekslar (ro'yxat kattalashganda kerak bo'ladi)
CREATE INDEX IF NOT EXISTS idx_yotq_kirish ON yotqizishlar (kirish_sana);
CREATE INDEX IF NOT EXISTS idx_yotq_chiqish ON yotqizishlar (haqiqiy_chiqish);
CREATE INDEX IF NOT EXISTS idx_tolov_sana ON tolovlar (sana);

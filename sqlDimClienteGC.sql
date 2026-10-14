-- =====================================================================
-- DIM_CLIENTE_UNICO
-- =====================================================================
-- REGRAS
--
-- EMPRESAS / WEB
--   G_<GROUPER>
--   N_<NOME_NORMALIZADO>
--
--   Priorização:
--      1) Maior TPV
--      2) Maior data transação
--      3) Maior cod_customer_grouper
--
-- NOVOS NEGÓCIOS
--   P_<PARCEIRO_NORMALIZADO>
--   Não participa do ranking TPV
--
-- SAÍDA
--   cliente_unico_key
--   cliente_unico
--   cod_customer_grouper
-- =====================================================================
-- 🔹 2. CARTEIRA FOTO (jan/2026) ---------------------------------------
DROP TABLE IF EXISTS #carteira_foto;
CREATE TEMP TABLE #carteira_foto
--create table planejamentocomercial_work.ws_carteira_foto
DISTKEY(idt_safepay_user)
SORTKEY(idt_safepay_user)
AS
--carteira_foto AS (
    SELECT DISTINCT
        idt_safepay_user,
        CASE WHEN cod_customer_grouper IN (60957,22834,22836,43156639,22570,26729,17655,22835,24913,6006) THEN 'Web'
             WHEN des_portfolio = 'Empresas' AND des_segment LIKE '%Web%' THEN 'Web'
             ELSE des_portfolio END AS des_portfolio,
        CASE WHEN cod_customer_grouper IN (60957,22834,22836,43156639,22570,26729,17655,22835,24913,6006) THEN 'Web'
             ELSE des_segment END AS des_segment
             --into #carteira_foto
    FROM dax_share_dax.ent_customer_portfolio_psp
    WHERE dat_reference = LAST_DAY('2026-01-01'::DATE)
    AND des_segment <> 'Clientes internos';
-- 🔹 2. CARTEIRA FOTO (jan/2026) ---------------------------------------
DROP TABLE IF EXISTS #base_cliente;
CREATE TEMP TABLE #base_cliente
DISTKEY(idt_safepay_user)
SORTKEY(dat_reference,idt_safepay_user)
AS
SELECT
       ecpp.idt_safepay_user
      ,DATE_TRUNC('month', ecpp.dat_reference::DATE) AS dat_reference
     ,CASE WHEN ecpp.cod_customer_grouper IN (60957,22834,22836,43156639,22570,26729,17655,22835,24913,6006) THEN 'Web'
          WHEN LAST_DAY(ecpp.dat_reference) <= LAST_DAY('2025-12-01') THEN foto.des_portfolio
          WHEN ecpp.des_portfolio = 'Empresas' AND ecpp.des_segment LIKE '%Web%' THEN 'Web'
          ELSE ISNULL(ecpp.des_portfolio, 'Varejo') END AS carteira       
    , ecpp.cod_customer_grouper 
    , UPPER(
        REPLACE(
            ISNULL(
                CASE
                    WHEN [carteira] = 'Novos Negócios'
                        THEN ISNULL(
                                RTRIM(
    REPLACE(ecpp.nam_business_partner, '.', '')
									),
                                'SEM PARCEIRO'
                             )
                    WHEN ecp.nam_seller_chain <> 'NI'
                        THEN ecp.nam_seller_chain
                    WHEN ecp.nam_leg_ent_corp <> 'NI'
                        THEN ecp.nam_leg_ent_corp
                    WHEN ecp.nam_leg_ent_trade <> 'NI'
                        THEN ecp.nam_leg_ent_trade
                    ELSE ecp.nam_ind
                END
            ,'SEM CADASTRO')
        ,'|','')
    ) AS cliente_unico
    , CASE
        ---------------------------------------------------------------
        -- NOVOS NEGÓCIOS
        ---------------------------------------------------------------
        WHEN [carteira] = 'Novos Negócios'
        THEN
            'P_' ||
            REGEXP_REPLACE(
                TRANSLATE(
                    UPPER(
                        TRIM(
                            ISNULL(
                                ecpp.nam_business_partner,
                                'SEM PARCEIRO'
                            )
                        )
                    )
                ,
                'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
                'AAAAAEEEEIIIIOOOOOUUUUCN'
                )
            ,'[^A-Z0-9]'
            ,''
            )
        ---------------------------------------------------------------
        -- EMPRESAS / WEB COM GROUPER
        ---------------------------------------------------------------
        WHEN ecpp.cod_customer_grouper IS NOT NULL
         AND ecpp.cod_customer_grouper <> -1
        THEN
            'G_' || ecpp.cod_customer_grouper::VARCHAR
        ---------------------------------------------------------------
        -- FALLBACK POR NOME
        ---------------------------------------------------------------
        ELSE
            'N_' ||
            REGEXP_REPLACE(
                TRANSLATE(
                    UPPER(
                        ISNULL(
                            [cliente_unico]
                        ,'SEM CADASTRO')
                    )
                ,
                'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
                'AAAAAEEEEIIIIOOOOOUUUUCN'
                )
            ,'[^A-Z0-9]'
            ,''
            )
      END AS cliente_unico_key
    , GREATEST(
          ecp.dat_last_paid_transaction
        , ecp.dat_last_paid_tran_mobile
      ) AS dat_last_paid_transaction
FROM dax_share_dax.ent_customer_portfolio_psp ecpp
JOIN dax_share_dax.ent_customer_psp ecp
    ON ecpp.idt_safepay_user = ecp.idt_safepay_user
LEFT JOIN #carteira_foto foto	ON foto.idt_safepay_user = ecpp.idt_safepay_user
WHERE 1=1
and  last_day(ecpp.dat_reference::DATE) >= last_day('2024-01-01')
group by all;
-- =====================================================================
-- TPV SOMENTE EMPRESAS / WEB
-- =====================================================================
DROP TABLE IF EXISTS #tpv_ranking;
CREATE TEMP TABLE #tpv_ranking
DISTKEY(cliente_unico_key)
SORTKEY(dat_reference,cliente_unico_key)
AS
select
	  b.dat_reference
    , b.cliente_unico_key
    , b.cliente_unico
    , b.cod_customer_grouper
    , MAX(b.dat_last_paid_transaction) AS dat_last_paid_transaction
    , SUM(ms.num_tpv_value)            AS tpv
FROM #base_cliente b
JOIN dax_share_dax.ent_margin_summary ms
   ON ms.idt_safepay_creditor = b.idt_safepay_user
   AND LAST_DAY(ms.dat_reference) = LAST_DAY(b.dat_reference)
WHERE b.carteira IN ('Empresas','Web')
AND last_day(ms.dat_reference::DATE) >= last_day('2024-01-01')
GROUP BY
      1, 2, 3, 4;
-- =====================================================================
-- RANKING EMPRESAS / WEB
-- =====================================================================
DROP TABLE IF EXISTS #ranking_cliente;
CREATE TEMP TABLE #ranking_cliente
DISTKEY(cod_customer_grouper)
SORTKEY(dat_reference,cod_customer_grouper)
AS
SELECT
      *
    , ROW_NUMBER() OVER (
        PARTITION BY cod_customer_grouper
        ORDER BY
              tpv DESC
            , dat_last_paid_transaction desc
            , COALESCE(cod_customer_grouper,-1) desc
      ) AS rn
FROM #tpv_ranking; 
-- DIMENSÃO FINAL
-- =====================================================================
SELECT distinct
      cliente_unico_key
    , cliente_unico
    , cod_customer_grouper
FROM #ranking_cliente
WHERE rn = 1
UNION ALL
SELECT DISTINCT
      cliente_unico_key
    , cliente_unico
    , CAST(-1 AS BIGINT) AS cod_customer_grouper
FROM #base_cliente
WHERE carteira = 'Novos Negócios';
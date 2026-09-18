/*
	Regras finais (usando dat_start):
	INCREMENTO  → teve TPV no mês imediatamente anterior ao dat_start
	NOVO        → credenciado no mês atual e (primeiro TPV no mês do credenciamento ou nunca transacionou)
	REATIVAÇÃO  → demais casos
*/

-- Base de credenciamentos do polo
drop table if exists #tbl_vl_extc_polo;
select 
    idt_safepay_user,
    des_cpf,
    des_customer_type,
    des_origin,
    dat_start::date as dat_start,
    last_day(dat_start::date) as mes_start,
    nam_current_executive, 
    nam_executive,
    nam_polo,
	cod_cart,
	cod_mcc,
    sum(case when last_day(dat_start::date) = dat_reference_values then num_tpv_value else 0 end) as tpv,
    cast(0 as decimal(10,2)) as tpv_m_menos_1,
    cast(null as varchar(20)) as tipo_credenciamento,
    cast(null as date) as first_tpv_date
into #tbl_vl_extc_polo
from comercial.tbl_vl_extc_polo
where polo_empresas in (0,2,3)
and dat_start >= '2025-01-01'
group by 
    idt_safepay_user,
    des_cpf,
    des_customer_type,
    des_origin,
    dat_start::date,
    last_day(dat_start::date),
    nam_current_executive, 
    nam_executive,
    nam_polo,
	cod_cart,
	cod_mcc;

----- Histórico mensal de TPV
drop table if exists #TPV;
select 
    idt_safepay_creditor,
    last_day(dat_reference) as dat_reference,
    sum(num_tpv_value) as tpv
into #TPV
from dax.ent_margin_summary
where idt_safepay_creditor in (
    select idt_safepay_user from #tbl_vl_extc_polo)
group by 1,2;

---- Primeiro mês com TPV da vida do cliente
drop table if exists #TPV_FIRST;
select
    idt_safepay_creditor,
    min(dat_reference) as first_tpv_date
into #TPV_FIRST
from #TPV
where tpv > 0
group by 1;

--Marcando a primeira transação
update #tbl_vl_extc_polo 
set first_tpv_date = xx.first_tpv_date
from #tbl_vl_extc_polo t1 
inner join #TPV_FIRST xx on xx.idt_safepay_creditor = t1.idt_safepay_user
where 1=1;

--Marca se teve TPV no mês anterior ao credenciamento
update #tbl_vl_extc_polo 
set tpv_m_menos_1 = xx.tpv
from #tbl_vl_extc_polo t1
inner join #TPV xx on xx.idt_safepay_creditor = t1.idt_safepay_user and xx.dat_reference = last_day(dateadd(month, -1, t1.dat_start))
where 1=1;

update #tbl_vl_extc_polo
set tipo_credenciamento = 'INCREMENTO'
from #tbl_vl_extc_polo t1
inner join #TPV t on t.idt_safepay_creditor = t1.idt_safepay_user 					/* ids iguais entre bases */
				  and t.dat_reference = last_day(dateadd(month, -1, t1.dat_start)) 	/* a data do tpv é igual ao mês anterior ao credenciamento */
				  and t.tpv > 0 													/* o tpv do mês anterior é maior que zero */
where t1.tpv > 0; 	

---------- NOVO
-- Credenciado no mês atual
-- e primeiro TPV no mês do credenciamento ou nunca transacionou
update #tbl_vl_extc_polo
set tipo_credenciamento = 'NOVO'
where tipo_credenciamento is null
  and not exists (
      select 1
      from #TPV
      where #TPV.idt_safepay_creditor = #tbl_vl_extc_polo.idt_safepay_user
        and #TPV.dat_reference < #tbl_vl_extc_polo.mes_start
  );

--CLIENTES QUE AINDA NÃO TRANSACIONARAM SÃO MARCADOS COMO NOVO
update #tbl_vl_extc_polo set tipo_credenciamento = 'NOVO' 
where tipo_credenciamento is null 
and tpv = 0 
and first_tpv_date is null; 
 
-- REATIVAÇÃO
update #tbl_vl_extc_polo
set tipo_credenciamento = 'REATIVAÇÃO'
where tipo_credenciamento is null;

select 
	count(distinct idt_safepay_user) as cred
	, count(distinct case when tipo_credenciamento = 'INCREMENTO' then idt_safepay_user end) as incremento
	, count(distinct case when tipo_credenciamento = 'NOVO' then idt_safepay_user end) as novos
	, count(distinct case when tipo_credenciamento = 'REATIVAÇÃO' then idt_safepay_user end) as reativacoes
	, dat_start::date as dat_cred
	, cod_cart
	, des_customer_type
	, cod_mcc
from 
	#tbl_vl_extc_polo
	Where last_day(dat_start::date) BETWEEN 
        dateadd(month, -5, last_day(current_date)) AND last_day(current_date)
    OR last_day(dat_start::date) = dateadd(year, -1, last_day(current_date))
	group by 
	dat_start::date
	, cod_cart
	, des_customer_type
	, cod_mcc;
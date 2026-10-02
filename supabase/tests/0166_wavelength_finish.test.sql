begin;
select plan(23);

\ir support/harness.psql

create function tests.wl_finish_deal(p_mode text, p_preset text, out match_id uuid)
returns uuid language plpgsql as $$
declare v_match_id uuid;
begin
  v_match_id := tests.mkmatch(case when p_mode = 'coop' then 2 else 4 end, 'wavelength_2v2');
  perform tests.act_as_admin();
  perform wavelength_private.deal_board(v_match_id, p_mode, p_preset, .25);
  update public.matches set status = 'playing', started_at = now() where id = v_match_id;
  update public.wavelength_rounds r set status = 'locked', points = 0, revealed_target = t.target
    from public.wavelength_targets t
   where r.match_id = v_match_id and t.match_id = r.match_id and t.round = r.round;
  match_id := v_match_id;
end $$;

create function tests.wl_set_coop_score(p_match uuid, p_score int) returns void language plpgsql as $$
declare v_left int := p_score; v_round record; v_points int;
begin
  for v_round in select round from public.wavelength_rounds where match_id = p_match order by round loop
    v_points := least(4, v_left);
    update public.wavelength_rounds set points = v_points where match_id = p_match and round = v_round.round;
    v_left := v_left - v_points;
  end loop;
  perform wavelength_private.finish_if_ready(p_match);
end $$;

-- Co-op always resolves after its board, including a loss, and the first star
-- is the target itself rather than an implicit early finish.
insert into tests.fx (k, v) values ('short_loss', tests.wl_finish_deal('coop', 'short'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'short_loss'), 7);
select is((select outcome from public.wavelength_results where match_id = (select v from tests.fx where k = 'short_loss')), 'lose', 'short below target loses');
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'short_loss')), 0, 'short below target has no stars');

insert into tests.fx (k, v) values ('short_target', tests.wl_finish_deal('coop', 'short'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'short_target'), 8);
select is((select outcome from public.wavelength_results where match_id = (select v from tests.fx where k = 'short_target')), 'win', 'short target wins');
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'short_target')), 1, 'short target has one star');

insert into tests.fx (k, v) values ('short_two', tests.wl_finish_deal('coop', 'short'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'short_two'), 12);
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'short_two')), 2, 'short second threshold has two stars');
insert into tests.fx (k, v) values ('short_three', tests.wl_finish_deal('coop', 'short'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'short_three'), 15);
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'short_three')), 3, 'short third threshold has three stars');

insert into tests.fx (k, v) values ('medium', tests.wl_finish_deal('coop', 'medium'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'medium'), 18);
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'medium')), 2, 'medium second threshold has two stars');
insert into tests.fx (k, v) values ('medium3', tests.wl_finish_deal('coop', 'medium'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'medium3'), 22);
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'medium3')), 3, 'medium third threshold has three stars');
insert into tests.fx (k, v) values ('long', tests.wl_finish_deal('coop', 'long'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'long'), 24);
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'long')), 2, 'long second threshold has two stars');
insert into tests.fx (k, v) values ('long3', tests.wl_finish_deal('coop', 'long'));
select tests.wl_set_coop_score((select v from tests.fx where k = 'long3'), 29);
select is((select stars::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'long3')), 3, 'long third threshold has three stars');
select is((select score::int from public.wavelength_results where match_id = (select v from tests.fx where k = 'long3')), 29, 'result retains the co-op score');
select is((select phase from public.wavelength_matches where match_id = (select v from tests.fx where k = 'long3')), 'complete', 'co-op completion updates the game board');

-- Different totals rank every member of the higher-scoring team first, with
-- team copied to the platform handoff rows.
insert into tests.fx (k, v) values ('versus', tests.wl_finish_deal('versus', null));
update public.wavelength_rounds r set points = case when p.team = 0 then 4 else 2 end
  from public.wavelength_players p where r.match_id = (select v from tests.fx where k = 'versus') and p.match_id = r.match_id and p.user_id = r.psychic_id;
select wavelength_private.finish_if_ready((select v from tests.fx where k = 'versus'));
select is((select array_agg(placement order by team, user_id) from public.match_players where match_id = (select v from tests.fx where k = 'versus')), array[1,1,3,3]::smallint[], 'higher total team places first');
select is((select array_agg(raw_score::int order by team, user_id) from public.match_players where match_id = (select v from tests.fx where k = 'versus')), array[16004,16004,8000,8000], 'versus handoff encodes score and bullseyes');
select is((select count(*)::int from public.match_players where match_id = (select v from tests.fx where k = 'versus') and team is not null), 4, 'handoff records each player team');

-- Equal totals are ranked by bullseyes before sudden death is considered.
insert into tests.fx (k, v) values ('bullseye', tests.wl_finish_deal('versus', null));
with numbered as (
  select r.round, p.team, row_number() over (partition by p.team order by r.round) n
    from public.wavelength_rounds r join public.wavelength_players p on p.match_id = r.match_id and p.user_id = r.psychic_id
   where r.match_id = (select v from tests.fx where k = 'bullseye')
)
update public.wavelength_rounds r set points = case when n.team = 0 and n.n = 1 then 4 when n.team = 1 and n.n in (1,2) then 2 else 0 end
  from numbered n where r.match_id = (select v from tests.fx where k = 'bullseye') and r.round = n.round;
select wavelength_private.finish_if_ready((select v from tests.fx where k = 'bullseye'));
select is((select array_agg(placement order by team, user_id) from public.match_players where match_id = (select v from tests.fx where k = 'bullseye')), array[1,1,3,3]::smallint[], 'bullseye tiebreak ranks team zero first');
select is((select outcome from public.wavelength_results where match_id = (select v from tests.fx where k = 'bullseye')), 'team_0_win', 'versus result names the winning team');

-- A complete tie makes fresh two-round sudden death pairs until one leads.
insert into tests.fx (k, v) values ('sudden', tests.wl_finish_deal('versus', null));
select wavelength_private.finish_if_ready((select v from tests.fx where k = 'sudden'));
select is((select phase from public.wavelength_matches where match_id = (select v from tests.fx where k = 'sudden')), 'fill', 'full tie enters sudden-death fill');
select is((select count(*)::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'sudden')), 10, 'sudden death adds one clue per team');
select is((select count(*)::int = count(distinct card_id) from public.wavelength_cards where match_id = (select v from tests.fx where k = 'sudden')), true, 'sudden-death cards never repeat');
update public.wavelength_rounds r set status = 'locked', points = 0, revealed_target = t.target from public.wavelength_targets t where r.match_id = (select v from tests.fx where k = 'sudden') and r.match_id = t.match_id and r.round = t.round and r.round > 8;
select wavelength_private.finish_if_ready((select v from tests.fx where k = 'sudden'));
select is((select count(*)::int from public.wavelength_rounds where match_id = (select v from tests.fx where k = 'sudden')), 12, 'a tied sudden-death pair repeats');
update public.wavelength_rounds r set status = 'locked', points = case when r.round = 11 then 4 else 0 end, revealed_target = t.target from public.wavelength_targets t where r.match_id = (select v from tests.fx where k = 'sudden') and r.match_id = t.match_id and r.round = t.round and r.round > 10;
select wavelength_private.finish_if_ready((select v from tests.fx where k = 'sudden'));
select is((select phase from public.wavelength_matches where match_id = (select v from tests.fx where k = 'sudden')), 'complete', 'a decisive sudden-death pair completes the match');
select is((select count(*)::int = count(distinct card_id) from public.wavelength_cards where match_id = (select v from tests.fx where k = 'sudden')), true, 'repeated sudden death also uses only fresh cards');

select * from finish();
rollback;

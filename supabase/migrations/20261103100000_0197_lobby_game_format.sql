-- The room's "next up" settings, kept where everybody in the room can read them.
--
-- 0078 gave a room a durable "chosen but not yet started" game. The host also
-- sets that game up before starting it (scoring, era, roster, mode), and until
-- now those choices lived only in the host's client until `start_run`, so
-- nobody else in the room could see what they were about to play. This adds the
-- one column that holds them.
--
-- Shape: an object keyed by game name (`higher_or_lower`, `auction_team_builder`,
-- `wavelength_2v2`, `sabotage_draft`), each value that game's own settings
-- object. Keyed rather than flat so the host can set up several games while
-- browsing them and switching the pick doesn't lose the others' settings.
--
-- The platform does not interpret it, the same way it does not know what a game
-- is (see 0009's header): each client reads and writes the keys its own game
-- needs, and the game's `start` still takes the settings it is dealt with.
-- That is also why this is a free-form object and not a column per setting:
-- adding a setting to a game must not need a platform migration. The cap only
-- keeps a room's row from being used as storage.
--
-- Readable by members through the existing `lobbies_select_member` policy and
-- already on the lobby Realtime channel, since it is a column on `lobbies`.
alter table public.lobbies
  add column game_format jsonb not null default '{}'::jsonb
    constraint lobbies_game_format_object check (jsonb_typeof(game_format) = 'object')
    constraint lobbies_game_format_size check (octet_length(game_format::text) <= 4096);

-- The write side: the same guard sequence as `select_lobby_game` (auth, real
-- account, room exists and is open, caller is host and still a member), because
-- it is the same question - may this person steer the room? Replaces the whole
-- blob: the host's client holds all of it, so there is no merge to get wrong.
create function public.set_lobby_game_format(p_lobby_id uuid, p_format jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_lobby public.lobbies;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if (auth.jwt() ->> 'is_anonymous')::boolean is true then
    raise exception 'account_required' using errcode = '42501';
  end if;

  select * into v_lobby from public.lobbies where id = p_lobby_id for update;
  if not found then
    raise exception 'lobby_not_found' using errcode = 'P0001';
  end if;

  if v_lobby.closed_at is not null then
    raise exception 'lobby_closed' using errcode = 'P0001';
  end if;

  if v_lobby.host_id <> v_user then
    raise exception 'not_host' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.lobby_members
     where lobby_id = p_lobby_id and user_id = v_user and left_at is null
  ) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  update public.lobbies set game_format = coalesce(p_format, '{}'::jsonb) where id = p_lobby_id;
end;
$$;

revoke all on function public.set_lobby_game_format(uuid, jsonb) from public, anon;
grant execute on function public.set_lobby_game_format(uuid, jsonb) to authenticated;

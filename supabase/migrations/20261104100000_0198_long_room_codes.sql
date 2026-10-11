-- Room codes become unguessable link tokens.
--
-- A code used to be five characters, short enough to read aloud and type in.
-- Rooms are now joined by invite or by link, so nobody types one, and five
-- characters (~28.6M combinations) is a thin secret for something that lets
-- whoever holds it into a room. New rooms get 16 characters (~7e23), which no
-- one can enumerate. The column keeps its name and the same alphabet; rooms
-- already open keep their five-character codes until they close, so the check
-- accepts both lengths.

alter table public.lobbies drop constraint lobbies_code_check;
alter table public.lobbies
  add constraint lobbies_code_check check (code ~ '^[A-Z0-9]{5,32}$');

create or replace function private.generate_lobby_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
           substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ',
                  1 + floor(random() * 31)::int, 1),
           '')
  from generate_series(1, 16);
$$;

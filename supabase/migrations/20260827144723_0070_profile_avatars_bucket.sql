-- A public Storage bucket for user-uploaded profile avatars.
--
-- Public, like 0068's team-logos bucket: once a player sets an avatar it's
-- shown to every co-player in a lobby/match (ProfileAvatar, roster lists),
-- so there's no read to gate. What needs gating is the write: a signed-in
-- user may only write under a path prefixed with their own uid, enforced
-- below via storage.objects RLS rather than at the application layer, so a
-- stolen anon key can't be used to overwrite another player's avatar.
--
-- Path convention: `{user_id}/{filename}`. The first path segment is
-- compared against auth.uid() by every policy below.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy avatars_read_all on storage.objects
  for select
  using (bucket_id = 'avatars');

create policy avatars_insert_own on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_update_own on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_delete_own on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

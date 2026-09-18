# Local development

## Database reset

When resetting the local Supabase stack, run `npm --prefix webapp run db:reset`. It applies migrations and `supabase/seed.sql`, then restores the NFL logo PNGs to the local `team-logos` Storage bucket. This is the complete local reset; `supabase db reset` alone leaves that bucket without its objects.

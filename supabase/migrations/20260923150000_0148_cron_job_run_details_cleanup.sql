-- cron.job_run_details logs every run of every pg_cron job and is never pruned
-- on its own. Several jobs run every 30 seconds to a minute, so the table
-- grows unbounded (~53MB / 326k rows after 44 days in production). Add a
-- daily cleanup job that keeps a week of history for debugging and discards
-- the rest.

create function private.cleanup_cron_job_run_details()
returns void
language sql security definer set search_path = ''
as $$
  delete from cron.job_run_details
   where end_time < now() - interval '7 days';
$$;

select cron.schedule('cron-job-run-details-cleanup', '0 4 * * *', $$ select private.cleanup_cron_job_run_details() $$);

revoke all on function private.cleanup_cron_job_run_details() from public, anon, authenticated;

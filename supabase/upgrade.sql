-- BloodCare consolidated incremental upgrade
-- Intended for an existing BloodCare database. Existing rows are preserved.
-- Review and paste this file into Supabase SQL Editor when bringing an older BloodCare database to the current schema.

-- Core workflow and operational settings
-- Safe to run on an existing BloodDonorV3 / BloodCare 3 database.
-- Existing records are preserved. Run this file in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- ============================================================
-- Configurable operational defaults
-- ============================================================
create table if not exists public.system_settings (
  id integer primary key default 1 check(id=1),
  donation_interval_days integer not null default 90 check(donation_interval_days between 1 and 365),
  appointment_slot_limit integer not null default 6 check(appointment_slot_limit between 1 and 100),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
insert into public.system_settings(id) values(1) on conflict(id) do nothing;

grant select on public.system_settings to authenticated;
grant update on public.system_settings to authenticated;

alter table public.system_settings enable row level security;
drop policy if exists "staff settings read" on public.system_settings;
drop policy if exists "admin settings update" on public.system_settings;
create policy "staff settings read" on public.system_settings for select to authenticated using(public.is_staff());
create policy "admin settings update" on public.system_settings for update to authenticated using(public.is_admin()) with check(public.is_admin());

-- ============================================================
-- Schema extensions
-- ============================================================
alter table public.appointments add column if not exists facility_id uuid references public.facilities(id) on delete set null;
alter table public.blood_requests add column if not exists reserved_at timestamptz;

-- Inventory movements now record reservation lifecycle as well.
alter table public.inventory_transactions drop constraint if exists inventory_transactions_transaction_type_check;
alter table public.inventory_transactions add constraint inventory_transactions_transaction_type_check
  check(transaction_type in ('donation','release','adjustment','expired','discarded','transfer_in','transfer_out','reservation','reservation_release'));

-- Useful indexes for the larger management lists and reservation workflow.
create index if not exists donors_created_at_idx on public.donors(created_at desc);
create index if not exists donors_email_birth_idx on public.donors(lower(email),birth_date);
create index if not exists requests_status_created_idx on public.blood_requests(status,created_at desc);
create index if not exists appointments_date_status_idx on public.appointments(appointment_date,status);
create index if not exists units_type_status_expiry_idx on public.blood_units(blood_type,status,expiry_date);
create index if not exists units_request_status_idx on public.blood_units(request_id,status);
create index if not exists events_publish_date_idx on public.events(published,event_date desc);
create index if not exists announcements_publish_created_idx on public.announcements(published,created_at desc);

-- ============================================================
-- Normalization and expiry maintenance
-- ============================================================
create or replace function public.normalize_phone(p_phone text)
returns text language sql immutable as $$
  select case
    when regexp_replace(coalesce(p_phone,''),'[^0-9+]','','g') like '+63%' then regexp_replace(coalesce(p_phone,''),'[^0-9+]','','g')
    when regexp_replace(coalesce(p_phone,''),'[^0-9]','','g') like '09%' then '+63'||substring(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g') from 2)
    else regexp_replace(coalesce(p_phone,''),'[^0-9+]','','g')
  end
$$;

create or replace function public.refresh_expired_units()
returns integer language plpgsql security definer set search_path=public as $$
declare r record; v_count integer:=0; v_balance integer;
begin
  perform pg_advisory_xact_lock(hashtext('bloodcare_refresh_expired_units'));
  for r in
    select blood_type,count(*)::integer as qty
    from public.blood_units
    where status='available' and expiry_date is not null and expiry_date < current_date
    group by blood_type
  loop
    update public.blood_units
      set status='expired',updated_at=now()
      where blood_type=r.blood_type and status='available' and expiry_date is not null and expiry_date < current_date;
    update public.blood_inventory
      set bags_available=greatest(0,bags_available-r.qty),updated_at=now()
      where blood_type=r.blood_type
      returning bags_available into v_balance;
    insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason)
      values(r.blood_type,-r.qty,coalesce(v_balance,0),'expired','Automatic expiry check');
    v_count:=v_count+r.qty;
  end loop;

  -- Reserved units that expired are removed from their request. They were already
  -- excluded from bags_available when reserved, so inventory is not decremented again.
  update public.blood_units
    set status='expired',request_id=null,updated_at=now()
    where status='reserved' and expiry_date is not null and expiry_date < current_date;

  return v_count;
end $$;
grant execute on function public.refresh_expired_units() to anon,authenticated;

create or replace function public.public_inventory()
returns table(blood_type text,bags_available integer,reorder_level integer,updated_at timestamptz)
language plpgsql security definer set search_path=public as $$
begin
  perform public.refresh_expired_units();
  return query select i.blood_type,i.bags_available,i.reorder_level,i.updated_at from public.blood_inventory i order by i.blood_type;
end $$;
grant execute on function public.public_inventory() to anon,authenticated;

-- ============================================================
-- Safer public submissions
-- ============================================================
create or replace function public.register_donor(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare v_code text; v_birth date; v_last date; v_email text; v_phone text;
begin
  v_birth:=nullif(p_data->>'birth_date','')::date;
  v_last:=nullif(p_data->>'last_donation_date','')::date;
  v_email:=lower(trim(p_data->>'email'));
  v_phone:=public.normalize_phone(p_data->>'phone');
  if v_birth is null or v_birth >= current_date then raise exception 'Birth date must be a valid past date'; end if;
  if v_last is not null and v_last > current_date then raise exception 'Last donation date cannot be in the future'; end if;
  if exists(select 1 from public.donors where lower(email)=v_email and birth_date=v_birth) then
    raise exception 'A donor with this email and birth date is already registered. Use your existing donor code or contact staff.';
  end if;
  if length(v_phone) < 7 then raise exception 'Enter a valid phone number'; end if;

  insert into public.donors(first_name,last_name,email,phone,birth_date,sex,blood_type,last_donation_date,barangay,municipality,street,province,notes)
  values(trim(p_data->>'first_name'),trim(p_data->>'last_name'),v_email,v_phone,
         v_birth,trim(p_data->>'sex'),trim(p_data->>'blood_type'),v_last,
         trim(p_data->>'barangay'),trim(p_data->>'municipality'),trim(p_data->>'street'),trim(p_data->>'province'),nullif(trim(p_data->>'notes'),''))
  returning donor_code into v_code;
  return v_code;
end $$;
grant execute on function public.register_donor(jsonb) to anon,authenticated;

create or replace function public.submit_blood_request(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare v_code text; v_needed date;
begin
  v_needed:=(p_data->>'date_needed')::date;
  if v_needed < current_date then raise exception 'Date needed cannot be in the past'; end if;
  insert into public.blood_requests(patient_name,requester_name,email,phone,blood_type,bags,hospital,date_needed,reason,status)
  values(trim(p_data->>'patient_name'),trim(p_data->>'requester_name'),lower(trim(p_data->>'email')),public.normalize_phone(p_data->>'phone'),
         trim(p_data->>'blood_type'),(p_data->>'bags')::integer,trim(p_data->>'hospital'),v_needed,trim(p_data->>'reason'),'pending')
  returning request_code into v_code;
  return v_code;
end $$;
grant execute on function public.submit_blood_request(jsonb) to anon,authenticated;

create or replace function public.submit_appointment(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare
  v_code text; v_donor public.donors%rowtype; v_donor_id uuid; v_type text;
  v_date date; v_time time; v_facility uuid; v_location text; v_email text; v_limit integer;
begin
  v_date:=(p_data->>'appointment_date')::date;
  v_time:=(p_data->>'appointment_time')::time;
  v_email:=lower(trim(p_data->>'email'));
  if v_date < current_date then raise exception 'Appointment date cannot be in the past'; end if;

  if nullif(trim(p_data->>'donor_code'),'') is not null then
    select * into v_donor from public.donors where donor_code=upper(trim(p_data->>'donor_code'));
    if not found then raise exception 'Donor code not found'; end if;
    if v_donor.status <> 'eligible' then raise exception 'This donor is not currently marked eligible for donation'; end if;
    v_donor_id:=v_donor.id; v_type:=v_donor.blood_type;
  else
    v_type:=trim(p_data->>'blood_type');
  end if;

  if nullif(trim(p_data->>'facility_id'),'') is not null then
    v_facility:=(p_data->>'facility_id')::uuid;
    select name into v_location from public.facilities where id=v_facility and active=true;
    if v_location is null then raise exception 'Selected donation facility is not available'; end if;
  else
    v_location:=trim(p_data->>'location');
    if length(v_location)<2 then raise exception 'Donation location is required'; end if;
  end if;

  if exists(
    select 1 from public.appointments a
    where a.appointment_date=v_date and a.appointment_time=v_time
      and a.status in ('requested','confirmed','checked_in')
      and ((v_donor_id is not null and a.donor_id=v_donor_id) or (v_donor_id is null and lower(a.email)=v_email))
  ) then raise exception 'You already have an active appointment for this date and time'; end if;

  select appointment_slot_limit into v_limit from public.system_settings where id=1;
  if (select count(*) from public.appointments a where a.appointment_date=v_date and a.appointment_time=v_time and coalesce(a.facility_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_facility,'00000000-0000-0000-0000-000000000000'::uuid) and a.status in ('requested','confirmed','checked_in')) >= coalesce(v_limit,6) then
    raise exception 'That appointment slot is already full. Please choose another time.';
  end if;

  insert into public.appointments(full_name,email,phone,blood_type,appointment_date,appointment_time,location,facility_id,donor_id,status)
  values(trim(p_data->>'full_name'),v_email,public.normalize_phone(p_data->>'phone'),v_type,v_date,v_time,v_location,v_facility,v_donor_id,'requested')
  returning appointment_code into v_code;
  return v_code;
end $$;
grant execute on function public.submit_appointment(jsonb) to anon,authenticated;

-- ============================================================
-- Reservation-aware request workflow
-- ============================================================
create or replace function public.reserve_blood_for_request(p_request_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_ids uuid[]; v_have integer; v_need integer; v_balance integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  perform public.refresh_expired_units();
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;

  select count(*)::integer into v_have from public.blood_units where request_id=r.id and status='reserved';
  v_need:=r.bags-v_have;
  if v_need>0 then
    select array_agg(id) into v_ids from (
      select id from public.blood_units
      where blood_type=r.blood_type and status='available' and (expiry_date is null or expiry_date>=current_date)
      order by expiry_date nulls last,collection_date nulls last,created_at
      limit v_need for update skip locked
    ) q;
    if coalesce(array_length(v_ids,1),0)<v_need then
      raise exception 'Insufficient unexpired inventory: % more bag(s) needed',v_need;
    end if;
    update public.blood_units set status='reserved',request_id=r.id,updated_at=now() where id=any(v_ids);
    update public.blood_inventory set bags_available=bags_available-v_need,updated_at=now() where blood_type=r.blood_type returning bags_available into v_balance;
    insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,request_id,performed_by)
      values(r.blood_type,-v_need,v_balance,'reservation','Reserved for '||r.request_code,r.id,auth.uid());
  end if;
  update public.blood_requests set reserved_at=coalesce(reserved_at,now()),updated_at=now() where id=r.id;
  return r.bags;
end $$;
grant execute on function public.reserve_blood_for_request(uuid) to authenticated;

create or replace function public.release_request_reservation(p_request_id uuid,p_reason text default 'Reservation released')
returns integer language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_qty integer; v_balance integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  select count(*)::integer into v_qty from public.blood_units where request_id=r.id and status='reserved';
  if v_qty>0 then
    update public.blood_units set status='available',request_id=null,updated_at=now() where request_id=r.id and status='reserved';
    update public.blood_inventory set bags_available=bags_available+v_qty,updated_at=now() where blood_type=r.blood_type returning bags_available into v_balance;
    insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,request_id,performed_by)
      values(r.blood_type,v_qty,v_balance,'reservation_release',coalesce(nullif(trim(p_reason),''),'Reservation released'),r.id,auth.uid());
  end if;
  update public.blood_requests set reserved_at=null,updated_at=now() where id=r.id;
  return v_qty;
end $$;
grant execute on function public.release_request_reservation(uuid,text) to authenticated;

create or replace function public.update_request_status(p_request_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_status not in ('pending','under_review','approved','ready_for_release','rejected','cancelled') then
    raise exception 'Use Release Blood to complete a request';
  end if;
  if p_status in ('approved','ready_for_release') then
    perform public.reserve_blood_for_request(p_request_id);
  elsif p_status in ('pending','under_review','rejected','cancelled') then
    perform public.release_request_reservation(p_request_id,'Status changed to '||replace(p_status,'_',' '));
  end if;
  update public.blood_requests set status=p_status,staff_notes=p_notes,processed_by=auth.uid(),updated_at=now() where id=p_request_id;
  if not found then raise exception 'Request not found'; end if;
end $$;
grant execute on function public.update_request_status(uuid,text,text) to authenticated;

create or replace function public.release_blood_request(p_request_id uuid,p_notes text default null)
returns text language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_unit_ids uuid[]; locked_count integer; v_release text;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  perform public.refresh_expired_units();
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if r.status not in ('approved','ready_for_release') then raise exception 'Request must be approved before blood can be released'; end if;

  perform public.reserve_blood_for_request(r.id);
  select array_agg(id) into v_unit_ids from (
    select id from public.blood_units where request_id=r.id and status='reserved'
    order by expiry_date nulls last,collection_date nulls last,created_at
    limit r.bags for update
  ) q;
  locked_count:=coalesce(array_length(v_unit_ids,1),0);
  if locked_count<r.bags then raise exception 'Reserved inventory is incomplete'; end if;

  update public.blood_units set status='released',updated_at=now() where id=any(v_unit_ids);
  insert into public.blood_releases(request_id,blood_type,bags,notes,released_by)
    values(r.id,r.blood_type,r.bags,p_notes,auth.uid()) returning release_code into v_release;
  update public.blood_requests set status='completed',reserved_at=null,staff_notes=coalesce(p_notes,staff_notes),processed_by=auth.uid(),updated_at=now() where id=r.id;
  return v_release;
end $$;
grant execute on function public.release_blood_request(uuid,text) to authenticated;

-- ============================================================
-- Public stats/profile with refreshed stock and eligibility date
-- ============================================================
create or replace function public.public_stats()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  perform public.refresh_expired_units();
  select jsonb_build_object(
    'registered_donors',(select count(*) from public.donors),
    'available_bags',(select coalesce(sum(bags_available),0) from public.blood_inventory)
  ) into v_result;
  return v_result;
end $$;
grant execute on function public.public_stats() to anon,authenticated;

create or replace function public.public_donor_profile(p_donor_code text,p_email text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_donor public.donors%rowtype; v_result jsonb; v_interval integer;
begin
  select * into v_donor from public.donors
  where upper(donor_code)=upper(trim(p_donor_code)) and lower(email)=lower(trim(p_email));
  if not found then return null; end if;
  select donation_interval_days into v_interval from public.system_settings where id=1;

  select jsonb_build_object(
    'profile',jsonb_build_object(
      'donor_code',v_donor.donor_code,'first_name',v_donor.first_name,'last_name',v_donor.last_name,
      'email',v_donor.email,'phone',v_donor.phone,'birth_date',v_donor.birth_date,'sex',v_donor.sex,
      'blood_type',v_donor.blood_type,'last_donation_date',v_donor.last_donation_date,
      'next_eligible_date',case when v_donor.last_donation_date is null then null else v_donor.last_donation_date+coalesce(v_interval,90) end,
      'barangay',v_donor.barangay,'municipality',v_donor.municipality,'street',v_donor.street,'province',v_donor.province,
      'status',v_donor.status,'created_at',v_donor.created_at,'updated_at',v_donor.updated_at
    ),
    'appointments',coalesce((select jsonb_agg(jsonb_build_object(
      'appointment_code',a.appointment_code,'appointment_date',a.appointment_date,'appointment_time',a.appointment_time,
      'location',a.location,'status',a.status
    ) order by a.appointment_date desc,a.appointment_time desc) from public.appointments a where a.donor_id=v_donor.id),'[]'::jsonb),
    'donations',coalesce((select jsonb_agg(jsonb_build_object(
      'donation_code',d.donation_code,'donation_date',d.donation_date,'blood_type',d.blood_type,'bags',d.bags,'donation_site',d.donation_site
    ) order by d.donation_date desc) from public.donations d where d.donor_id=v_donor.id),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.public_donor_profile(text,text) from public;
grant execute on function public.public_donor_profile(text,text) to anon,authenticated;

-- Staff can see settings; only admins can alter them directly under RLS.
-- Optional example:
-- update public.system_settings set donation_interval_days=90, appointment_slot_limit=6, updated_at=now(), updated_by=auth.uid() where id=1;

-- ============================================================
-- Donation-entry date safeguards
-- ============================================================
create or replace function public.record_donation_v2(
  p_donor_code text,p_bags integer,p_donation_date date,p_site text,p_appointment_id uuid default null,p_expiry_date date default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_donor public.donors%rowtype; v_donation_id uuid; v_code text; v_balance integer; i integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_bags < 1 or p_bags > 10 then raise exception 'Invalid bag count'; end if;
  if p_donation_date is null or p_donation_date > current_date then raise exception 'Donation date cannot be in the future'; end if;
  if p_expiry_date is not null and p_expiry_date < p_donation_date then raise exception 'Expiry date cannot be earlier than the donation date'; end if;
  if length(trim(coalesce(p_site,''))) < 2 then raise exception 'Donation site is required'; end if;
  select * into v_donor from public.donors where donor_code=upper(trim(p_donor_code)) for update;
  if not found then raise exception 'Donor code not found'; end if;
  if v_donor.status <> 'eligible' then raise exception 'Donor must be marked eligible before a donation can be recorded'; end if;
  if p_appointment_id is not null and not exists(select 1 from public.appointments where id=p_appointment_id and (donor_id=v_donor.id or donor_id is null)) then
    raise exception 'Appointment does not match this donor';
  end if;
  insert into public.donations(donor_id,donor_code,blood_type,bags,donation_date,donation_site,appointment_id,expiry_date,recorded_by)
  values(v_donor.id,v_donor.donor_code,v_donor.blood_type,p_bags,p_donation_date,trim(p_site),p_appointment_id,p_expiry_date,auth.uid())
  returning id,donation_code into v_donation_id,v_code;
  for i in 1..p_bags loop
    insert into public.blood_units(donation_id,donor_id,blood_type,collection_date,expiry_date,source,status)
    values(v_donation_id,v_donor.id,v_donor.blood_type,p_donation_date,p_expiry_date,'donation','available');
  end loop;
  update public.blood_inventory set bags_available=bags_available+p_bags,updated_at=now() where blood_type=v_donor.blood_type returning bags_available into v_balance;
  insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,donation_id,performed_by)
  values(v_donor.blood_type,p_bags,v_balance,'donation','Donation '||v_code,v_donation_id,auth.uid());
  update public.donors set last_donation_date=p_donation_date,updated_at=now() where id=v_donor.id;
  if p_appointment_id is not null then
    update public.appointments set donor_id=v_donor.id,status='completed',processed_by=auth.uid(),updated_at=now() where id=p_appointment_id;
  end if;
  return v_code;
end $$;
grant execute on function public.record_donation_v2(text,integer,date,text,uuid,date) to authenticated;

-- Audit administrator changes to operational settings.
drop trigger if exists audit_system_settings on public.system_settings;
create trigger audit_system_settings after update on public.system_settings
for each row execute function public.audit_row_change();

-- Donor screening, account linking, and facility-aware workflow
-- Included in the consolidated BloodCare upgrade path.
-- Existing records are preserved.

create extension if not exists pgcrypto;

-- ============================================================
-- Donor pre-screening fields and account linking
-- ============================================================
alter table public.donors add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
alter table public.donors add column if not exists weight_kg numeric(5,2);
alter table public.donors add column if not exists health_issues text;
alter table public.donors add column if not exists has_tattoo boolean not null default false;
alter table public.donors add column if not exists tattoo_date date;
alter table public.donors add column if not exists has_piercing boolean not null default false;
alter table public.donors add column if not exists piercing_date date;
alter table public.donors add column if not exists drinks_alcohol boolean not null default false;
alter table public.donors add column if not exists smokes boolean not null default false;
alter table public.donors add column if not exists other_habits text;
alter table public.donors add column if not exists pre_screened boolean not null default false;

create unique index if not exists donors_auth_user_unique_idx on public.donors(auth_user_id) where auth_user_id is not null;
create index if not exists donors_email_lower_v5_idx on public.donors(lower(email));

-- ============================================================
-- Facility-aware inventory and requests
-- ============================================================
alter table public.facilities add column if not exists district text;
alter table public.blood_units add column if not exists facility_id uuid references public.facilities(id) on delete set null;
alter table public.donations add column if not exists facility_id uuid references public.facilities(id) on delete set null;
alter table public.blood_requests add column if not exists facility_id uuid references public.facilities(id) on delete set null;
alter table public.blood_requests add column if not exists request_for text not null default 'other';
alter table public.blood_requests add column if not exists relationship text;
alter table public.blood_requests add column if not exists pickup_date date;
alter table public.blood_requests add column if not exists pickup_time time;

alter table public.blood_requests drop constraint if exists blood_requests_request_for_check;
alter table public.blood_requests add constraint blood_requests_request_for_check check(request_for in ('self','other'));

create index if not exists units_facility_type_status_idx on public.blood_units(facility_id,blood_type,status,expiry_date);
create index if not exists requests_facility_status_idx on public.blood_requests(facility_id,status,created_at desc);

-- If the installation has exactly one active facility, safely attach legacy/unassigned
-- units to it. With multiple facilities, stock remains unassigned until staff assigns it.
do $$
declare v_facility uuid; v_count integer;
begin
  select count(*) into v_count from public.facilities where active=true;
  if v_count=1 then
    select id into v_facility from public.facilities where active=true limit 1;
    update public.blood_units set facility_id=v_facility where facility_id is null;
    update public.donations set facility_id=v_facility where facility_id is null;
  end if;
end $$;

-- ============================================================
-- Unified public feeds: News / Events / Announcements
-- ============================================================
alter table public.announcements add column if not exists image_url text;
alter table public.announcements add column if not exists feed_type text not null default 'news';
alter table public.announcements drop constraint if exists announcements_feed_type_check;
alter table public.announcements add constraint announcements_feed_type_check check(feed_type in ('news','announcement'));
create index if not exists announcements_type_published_created_idx on public.announcements(feed_type,published,created_at desc);

-- ============================================================
-- Donor registration with required basic standards
-- ============================================================
create or replace function public.register_donor(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare
  v_code text; v_birth date; v_last date; v_email text; v_phone text; v_age integer;
  v_weight numeric(5,2); v_health text; v_tattoo boolean; v_piercing boolean;
  v_tattoo_date date; v_piercing_date date;
begin
  v_birth:=nullif(p_data->>'birth_date','')::date;
  v_last:=nullif(p_data->>'last_donation_date','')::date;
  v_email:=lower(trim(p_data->>'email'));
  v_phone:=public.normalize_phone(p_data->>'phone');
  v_weight:=nullif(p_data->>'weight_kg','')::numeric;
  v_health:=trim(coalesce(p_data->>'health_issues',''));
  v_tattoo:=coalesce(nullif(p_data->>'has_tattoo','')::boolean,false);
  v_piercing:=coalesce(nullif(p_data->>'has_piercing','')::boolean,false);
  v_tattoo_date:=nullif(p_data->>'tattoo_date','')::date;
  v_piercing_date:=nullif(p_data->>'piercing_date','')::date;

  if v_birth is null or v_birth >= current_date then raise exception 'Birth date must be a valid past date'; end if;
  v_age:=extract(year from age(current_date,v_birth))::integer;
  if v_age < 18 or v_age > 65 then raise exception 'Basic donor standard requires age 18 to 65'; end if;
  if v_weight is null or v_weight < 50 then raise exception 'Basic donor standard requires a minimum weight of 50 kg'; end if;
  if length(v_health)=0 then raise exception 'Health issues must be stated. Enter None if there are no known health issues.'; end if;
  if v_last is not null and v_last > current_date then raise exception 'Last donation date cannot be in the future'; end if;
  if v_tattoo and v_tattoo_date is null then raise exception 'Enter the date of the most recent tattoo'; end if;
  if v_piercing and v_piercing_date is null then raise exception 'Enter the date of the most recent piercing'; end if;
  if v_tattoo_date is not null and v_tattoo_date > current_date then raise exception 'Tattoo date cannot be in the future'; end if;
  if v_piercing_date is not null and v_piercing_date > current_date then raise exception 'Piercing date cannot be in the future'; end if;
  if exists(select 1 from public.donors where lower(email)=v_email and birth_date=v_birth) then
    raise exception 'A donor with this email and birth date is already registered.';
  end if;
  if length(v_phone) < 7 then raise exception 'Enter a valid phone number'; end if;

  insert into public.donors(
    auth_user_id,first_name,last_name,email,phone,birth_date,sex,blood_type,last_donation_date,
    barangay,municipality,street,province,notes,weight_kg,health_issues,has_tattoo,tattoo_date,
    has_piercing,piercing_date,drinks_alcohol,smokes,other_habits,pre_screened
  ) values(
    auth.uid(),trim(p_data->>'first_name'),trim(p_data->>'last_name'),v_email,v_phone,v_birth,
    trim(p_data->>'sex'),trim(p_data->>'blood_type'),v_last,trim(p_data->>'barangay'),
    trim(p_data->>'municipality'),trim(p_data->>'street'),trim(p_data->>'province'),
    nullif(trim(p_data->>'notes'),''),v_weight,v_health,v_tattoo,v_tattoo_date,v_piercing,
    v_piercing_date,coalesce(nullif(p_data->>'drinks_alcohol','')::boolean,false),
    coalesce(nullif(p_data->>'smokes','')::boolean,false),nullif(trim(p_data->>'other_habits'),''),true
  ) returning donor_code into v_code;
  return v_code;
end $$;
grant execute on function public.register_donor(jsonb) to anon,authenticated;

-- ============================================================
-- Public stock by partner facility
-- ============================================================
create or replace function public.public_facility_inventory(p_blood_type text)
returns table(
  facility_id uuid, facility_name text, facility_type text, district text,
  address text, barangay text, municipality text, province text,
  bags_available integer
) language plpgsql security definer set search_path=public as $$
begin
  perform public.refresh_expired_units();
  return query
  select f.id,f.name,f.facility_type,f.district,f.address,f.barangay,f.municipality,f.province,count(u.id)::integer
  from public.facilities f
  join public.blood_units u on u.facility_id=f.id
   and u.blood_type=trim(p_blood_type)
   and u.status='available'
   and (u.expiry_date is null or u.expiry_date>=current_date)
  where f.active=true
  group by f.id,f.name,f.facility_type,f.district,f.address,f.barangay,f.municipality,f.province
  having count(u.id)>0
  order by count(u.id) desc,f.name;
end $$;
grant execute on function public.public_facility_inventory(text) to anon,authenticated;

-- ============================================================
-- Blood request must point to a facility with available stock
-- ============================================================
create or replace function public.submit_blood_request(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare
  v_code text; v_needed date; v_facility uuid; v_bags integer; v_type text;
  v_available integer; v_for text; v_relationship text; v_pickup date; v_pickup_time time;
begin
  perform public.refresh_expired_units();
  v_needed:=(p_data->>'date_needed')::date;
  v_bags:=(p_data->>'bags')::integer;
  v_type:=trim(p_data->>'blood_type');
  v_for:=lower(trim(coalesce(p_data->>'request_for','other')));
  v_relationship:=trim(coalesce(p_data->>'relationship',''));
  v_facility:=nullif(trim(p_data->>'facility_id'),'')::uuid;
  v_pickup:=nullif(p_data->>'pickup_date','')::date;
  v_pickup_time:=nullif(p_data->>'pickup_time','')::time;

  if v_needed < current_date then raise exception 'Date needed cannot be in the past'; end if;
  if v_bags < 1 or v_bags > 20 then raise exception 'Number of bags must be between 1 and 20'; end if;
  if v_for not in ('self','other') then raise exception 'Choose whether the request is for yourself or another person'; end if;
  if v_for='self' then v_relationship:='Self';
  elsif length(v_relationship)=0 then raise exception 'State your relationship to the patient'; end if;
  if v_facility is null then raise exception 'Choose a partner facility with available stock'; end if;
  if not exists(select 1 from public.facilities where id=v_facility and active=true) then raise exception 'Selected facility is not available'; end if;
  if v_pickup is not null and v_pickup < current_date then raise exception 'Preferred pickup date cannot be in the past'; end if;

  select count(*)::integer into v_available
  from public.blood_units
  where facility_id=v_facility and blood_type=v_type and status='available'
    and (expiry_date is null or expiry_date>=current_date);
  if coalesce(v_available,0) < v_bags then
    raise exception 'That facility currently has only % available bag(s) of %',coalesce(v_available,0),v_type;
  end if;

  insert into public.blood_requests(
    patient_name,requester_name,email,phone,blood_type,bags,hospital,date_needed,reason,status,
    facility_id,request_for,relationship,pickup_date,pickup_time
  ) values(
    trim(p_data->>'patient_name'),trim(p_data->>'requester_name'),lower(trim(p_data->>'email')),
    public.normalize_phone(p_data->>'phone'),v_type,v_bags,trim(p_data->>'hospital'),v_needed,
    trim(p_data->>'reason'),'pending',v_facility,v_for,v_relationship,v_pickup,v_pickup_time
  ) returning request_code into v_code;
  return v_code;
end $$;
grant execute on function public.submit_blood_request(jsonb) to anon,authenticated;

-- ============================================================
-- Facility-aware reservation lifecycle
-- ============================================================
create or replace function public.reserve_blood_for_request(p_request_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_ids uuid[]; v_have integer; v_need integer; v_balance integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  perform public.refresh_expired_units();
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;

  select count(*)::integer into v_have from public.blood_units where request_id=r.id and status='reserved';
  v_need:=r.bags-v_have;
  if v_need>0 then
    select array_agg(id) into v_ids from (
      select id from public.blood_units
      where blood_type=r.blood_type and status='available'
        and (r.facility_id is null or facility_id=r.facility_id)
        and (expiry_date is null or expiry_date>=current_date)
      order by expiry_date nulls last,collection_date nulls last,created_at
      limit v_need for update skip locked
    ) q;
    if coalesce(array_length(v_ids,1),0)<v_need then
      raise exception 'Insufficient unexpired inventory at the selected facility: % more bag(s) needed',v_need;
    end if;
    update public.blood_units set status='reserved',request_id=r.id,updated_at=now() where id=any(v_ids);
    update public.blood_inventory set bags_available=bags_available-v_need,updated_at=now() where blood_type=r.blood_type returning bags_available into v_balance;
    insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,request_id,performed_by)
      values(r.blood_type,-v_need,v_balance,'reservation','Reserved for '||r.request_code,r.id,auth.uid());
  end if;
  update public.blood_requests set reserved_at=coalesce(reserved_at,now()),updated_at=now() where id=r.id;
  return r.bags;
end $$;
grant execute on function public.reserve_blood_for_request(uuid) to authenticated;

-- ============================================================
-- Donation recording with facility ownership for every blood unit
-- ============================================================
create or replace function public.record_donation_v3(
  p_donor_code text,p_bags integer,p_donation_date date,p_facility_id uuid,
  p_appointment_id uuid default null,p_expiry_date date default null
) returns text language plpgsql security definer set search_path=public as $$
declare
  v_donor public.donors%rowtype; v_donation_id uuid; v_code text; v_balance integer;
  v_site text; i integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_bags < 1 or p_bags > 10 then raise exception 'Invalid bag count'; end if;
  if p_donation_date is null or p_donation_date > current_date then raise exception 'Donation date cannot be in the future'; end if;
  if p_expiry_date is not null and p_expiry_date < p_donation_date then raise exception 'Expiry date cannot be earlier than the donation date'; end if;
  select name into v_site from public.facilities where id=p_facility_id and active=true;
  if v_site is null then raise exception 'Select an active donation facility'; end if;
  select * into v_donor from public.donors where donor_code=upper(trim(p_donor_code)) for update;
  if not found then raise exception 'Donor code not found'; end if;
  if v_donor.status <> 'eligible' then raise exception 'Donor must be marked eligible before a donation can be recorded'; end if;
  if p_appointment_id is not null and not exists(select 1 from public.appointments where id=p_appointment_id and (donor_id=v_donor.id or donor_id is null)) then
    raise exception 'Appointment does not match this donor';
  end if;

  insert into public.donations(donor_id,donor_code,blood_type,bags,donation_date,donation_site,facility_id,appointment_id,expiry_date,recorded_by)
  values(v_donor.id,v_donor.donor_code,v_donor.blood_type,p_bags,p_donation_date,v_site,p_facility_id,p_appointment_id,p_expiry_date,auth.uid())
  returning id,donation_code into v_donation_id,v_code;
  for i in 1..p_bags loop
    insert into public.blood_units(donation_id,donor_id,blood_type,collection_date,expiry_date,source,status,facility_id)
    values(v_donation_id,v_donor.id,v_donor.blood_type,p_donation_date,p_expiry_date,'donation','available',p_facility_id);
  end loop;
  update public.blood_inventory set bags_available=bags_available+p_bags,updated_at=now() where blood_type=v_donor.blood_type returning bags_available into v_balance;
  insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,donation_id,performed_by)
  values(v_donor.blood_type,p_bags,v_balance,'donation','Donation '||v_code||' at '||v_site,v_donation_id,auth.uid());
  update public.donors set last_donation_date=p_donation_date,updated_at=now() where id=v_donor.id;
  if p_appointment_id is not null then
    update public.appointments set donor_id=v_donor.id,status='completed',processed_by=auth.uid(),updated_at=now() where id=p_appointment_id;
  end if;
  return v_code;
end $$;
grant execute on function public.record_donation_v3(text,integer,date,uuid,uuid,date) to authenticated;

create or replace function public.set_blood_unit_facility(p_unit_id uuid,p_facility_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if not exists(select 1 from public.facilities where id=p_facility_id and active=true) then raise exception 'Facility not found or inactive'; end if;
  update public.blood_units set facility_id=p_facility_id,updated_at=now() where id=p_unit_id and status='available';
  if not found then raise exception 'Only available blood units can be reassigned to a facility'; end if;
end $$;
grant execute on function public.set_blood_unit_facility(uuid,uuid) to authenticated;

-- ============================================================
-- Logged-in BloodCare account profile (donor OR non-donor)
-- ============================================================
create or replace function public.my_bloodcare_profile()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_uid uuid:=auth.uid(); v_email text; v_name text; v_donor public.donors%rowtype;
  v_interval integer; v_result jsonb;
begin
  if v_uid is null then raise exception 'Login required'; end if;
  select lower(coalesce(email,'')),coalesce(raw_user_meta_data->>'full_name',split_part(email,'@',1))
    into v_email,v_name from auth.users where id=v_uid;

  -- Staff and administrator identities are management accounts, not donor accounts.
  -- Never auto-link a staff/admin login to a donor merely because an email matches.
  if exists(select 1 from public.staff_profiles s where s.id=v_uid and s.active=true) then
    return jsonb_build_object(
      'account',jsonb_build_object('id',v_uid,'email',v_email,'full_name',v_name),
      'profile',null,
      'appointments','[]'::jsonb,
      'donations','[]'::jsonb,
      'requests','[]'::jsonb
    );
  end if;

  select * into v_donor from public.donors d
  where d.auth_user_id=v_uid or (v_email<>'' and lower(d.email)=v_email)
  order by (d.auth_user_id=v_uid) desc,d.created_at desc limit 1;

  if found and v_donor.auth_user_id is null then
    update public.donors set auth_user_id=v_uid,updated_at=now() where id=v_donor.id and auth_user_id is null;
    v_donor.auth_user_id:=v_uid;
  end if;
  select donation_interval_days into v_interval from public.system_settings where id=1;

  select jsonb_build_object(
    'account',jsonb_build_object('id',v_uid,'email',v_email,'full_name',v_name),
    'profile',case when v_donor.id is null then null else jsonb_build_object(
      'donor_code',v_donor.donor_code,'first_name',v_donor.first_name,'last_name',v_donor.last_name,
      'email',v_donor.email,'phone',v_donor.phone,'birth_date',v_donor.birth_date,'sex',v_donor.sex,
      'blood_type',v_donor.blood_type,'weight_kg',v_donor.weight_kg,'health_issues',v_donor.health_issues,
      'last_donation_date',v_donor.last_donation_date,
      'next_eligible_date',case when v_donor.last_donation_date is null then null else v_donor.last_donation_date+coalesce(v_interval,90) end,
      'barangay',v_donor.barangay,'municipality',v_donor.municipality,'street',v_donor.street,'province',v_donor.province,
      'status',v_donor.status,'created_at',v_donor.created_at,'updated_at',v_donor.updated_at
    ) end,
    'appointments',coalesce((select jsonb_agg(jsonb_build_object(
      'appointment_code',a.appointment_code,'appointment_date',a.appointment_date,'appointment_time',a.appointment_time,
      'location',a.location,'status',a.status
    ) order by a.appointment_date desc,a.appointment_time desc)
      from public.appointments a where a.donor_id=v_donor.id or lower(a.email)=v_email),'[]'::jsonb),
    'donations',case when v_donor.id is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
      'donation_code',d.donation_code,'donation_date',d.donation_date,'blood_type',d.blood_type,
      'bags',d.bags,'donation_site',d.donation_site
    ) order by d.donation_date desc) from public.donations d where d.donor_id=v_donor.id),'[]'::jsonb) end,
    'requests',coalesce((select jsonb_agg(jsonb_build_object(
      'request_code',r.request_code,'blood_type',r.blood_type,'bags',r.bags,'patient_name',r.patient_name,
      'status',r.status,'date_needed',r.date_needed,'pickup_date',r.pickup_date,'pickup_time',r.pickup_time
    ) order by r.created_at desc) from public.blood_requests r where lower(r.email)=v_email),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.my_bloodcare_profile() from public;
grant execute on function public.my_bloodcare_profile() to authenticated;

-- Track the new columns in audit history through the existing table triggers.


-- ============================================================
-- Admin facility stock assignment
-- ============================================================
-- Admin facility stock assignment
-- Adds administrator-controlled movement of available units between facility stock locations.

create or replace function public.admin_move_blood_stock(
  p_blood_type text,
  p_quantity integer,
  p_to_facility uuid,
  p_from_facility uuid default null
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_ids uuid[];
  v_count integer;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 100 then raise exception 'Quantity must be between 1 and 100'; end if;
  if trim(coalesce(p_blood_type,'')) not in ('A+','A-','B+','B-','AB+','AB-','O+','O-') then raise exception 'Invalid blood type'; end if;
  if not exists(select 1 from public.facilities where id=p_to_facility and active=true) then raise exception 'Destination facility not found or inactive'; end if;
  if p_from_facility is not null and p_from_facility=p_to_facility then raise exception 'Source and destination facilities must be different'; end if;
  if p_from_facility is not null and not exists(select 1 from public.facilities where id=p_from_facility) then raise exception 'Source facility not found'; end if;

  perform public.refresh_expired_units();

  select array_agg(id) into v_ids from (
    select id
    from public.blood_units
    where blood_type=trim(p_blood_type)
      and status='available'
      and (expiry_date is null or expiry_date>=current_date)
      and ((p_from_facility is null and facility_id is null) or facility_id=p_from_facility)
    order by expiry_date nulls last,created_at,id
    limit p_quantity
    for update skip locked
  ) q;

  v_count:=coalesce(array_length(v_ids,1),0);
  if v_count < p_quantity then
    raise exception 'Only % available unit(s) were found in the selected source stock',v_count;
  end if;

  update public.blood_units
  set facility_id=p_to_facility,updated_at=now()
  where id=any(v_ids);

  return v_count;
end $$;

revoke all on function public.admin_move_blood_stock(text,integer,uuid,uuid) from public;
grant execute on function public.admin_move_blood_stock(text,integer,uuid,uuid) to authenticated;

-- ============================================================
-- Public contact inquiries
-- Visitors may submit a contact form without creating an account.
-- Only authenticated BloodCare staff may read or update submissions.
-- ============================================================
create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid default auth.uid() references auth.users(id) on delete set null,
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  email text not null check (char_length(trim(email)) between 5 and 254),
  phone text,
  inquiry_type text not null default 'general' check (inquiry_type in ('general','donation','blood-request','appointment','facility','technical','other')),
  message text not null check (char_length(trim(message)) between 10 and 3000),
  source_page text,
  status text not null default 'new' check (status in ('new','read','resolved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Existing BloodCare databases may already have contact_messages from an
-- earlier release. CREATE TABLE IF NOT EXISTS does not add later columns,
-- so keep this migration explicitly idempotent.
alter table public.contact_messages add column if not exists auth_user_id uuid;
alter table public.contact_messages add column if not exists source_page text;

alter table public.contact_messages enable row level security;

drop policy if exists "public contact submit" on public.contact_messages;
drop policy if exists "staff contact read" on public.contact_messages;
drop policy if exists "staff contact update" on public.contact_messages;

create policy "public contact submit" on public.contact_messages
  for insert to anon,authenticated with check (true);
create policy "staff contact read" on public.contact_messages
  for select to authenticated using (public.is_staff());
create policy "staff contact update" on public.contact_messages
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

revoke all on table public.contact_messages from anon,authenticated;
grant insert on table public.contact_messages to anon,authenticated;
grant select,update on table public.contact_messages to authenticated;




-- ============================================================
-- Secure public contact submission RPC
-- Visitors may submit a message, but never receive direct table access.
-- SECURITY DEFINER lets this narrow function insert while RLS continues
-- protecting contact_messages from direct anonymous reads/writes.
-- ============================================================
create or replace function public.submit_contact_message(
  p_full_name text,
  p_email text,
  p_phone text,
  p_inquiry_type text,
  p_message text,
  p_source_page text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_name text := trim(coalesce(p_full_name,''));
  v_email text := lower(trim(coalesce(p_email,'')));
  v_phone text := trim(coalesce(p_phone,''));
  v_type text := coalesce(nullif(trim(p_inquiry_type),''),'general');
  v_message text := trim(coalesce(p_message,''));
begin
  if char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'Please enter your full name.';
  end if;
  if char_length(v_email) < 5 or char_length(v_email) > 254 or position('@' in v_email) = 0 then
    raise exception 'Please enter a valid email address.';
  end if;
  if v_phone !~ '^[0-9]{7,15}$' then
    raise exception 'Contact number must contain 7 to 15 digits only.';
  end if;
  if v_type not in ('general','donation','blood-request','appointment','facility','technical','other') then
    raise exception 'Invalid inquiry type.';
  end if;
  if char_length(v_message) < 10 or char_length(v_message) > 3000 then
    raise exception 'Please enter a message with at least 10 characters.';
  end if;

  insert into public.contact_messages(
    auth_user_id, full_name, email, phone, inquiry_type, message, source_page, status
  ) values (
    auth.uid(), v_name, v_email, v_phone, v_type, v_message,
    nullif(trim(coalesce(p_source_page,'')),''), 'new'
  )
  returning id into v_id;

  return v_id;
end $$;

revoke all on function public.submit_contact_message(text,text,text,text,text,text) from public;
grant execute on function public.submit_contact_message(text,text,text,text,text,text) to anon,authenticated;

-- Do not expose direct anonymous/authenticated INSERT privileges. The RPC above
-- is the only public write path; staff read/update policies remain unchanged.
drop policy if exists "public contact submit" on public.contact_messages;
revoke insert on table public.contact_messages from anon,authenticated;

notify pgrst, 'reload schema';

-- ============================================================
-- Donor pre-screen expansion: detailed answers + server policy
-- ============================================================
alter table public.donors add column if not exists screening_answers jsonb not null default '{}'::jsonb;
alter table public.donors add column if not exists screening_outcome text;
alter table public.donors add column if not exists screening_reasons jsonb not null default '[]'::jsonb;
alter table public.donors add column if not exists screening_next_eligible_at timestamptz;
alter table public.donors add column if not exists screening_completed_at timestamptz;
alter table public.donors drop constraint if exists donors_screening_outcome_check;
alter table public.donors add constraint donors_screening_outcome_check
  check(screening_outcome is null or screening_outcome in ('preliminarily_eligible','temporarily_deferred','needs_review','not_eligible'));

create or replace function public.donor_screening_policy()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_interval integer;
begin
  select donation_interval_days into v_interval from public.system_settings where id=1;
  return jsonb_build_object(
    'donation_interval_days',coalesce(v_interval,90),
    'body_mod_wait_months',12,
    'alcohol_wait_hours',24,
    'nicotine_wait_hours',4
  );
end $$;
revoke all on function public.donor_screening_policy() from public,anon;
grant execute on function public.donor_screening_policy() to authenticated;

create or replace function public.register_donor(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare
  v_code text; v_birth date; v_last date; v_email text; v_phone text; v_age integer;
  v_weight numeric(5,2); v_health text; v_tattoo boolean; v_piercing boolean;
  v_tattoo_date date; v_piercing_date date; v_screen jsonb; v_permanent jsonb; v_review jsonb;
  v_current_illness boolean; v_antibiotics boolean; v_medication boolean; v_breastfeeding boolean;
  v_acupuncture boolean; v_acupuncture_date date; v_pregnancy text;
  v_alcohol_recent boolean; v_last_alcohol timestamptz; v_nicotine boolean; v_last_nicotine timestamptz;
  v_outcome text := 'preliminarily_eligible'; v_reasons jsonb := '[]'::jsonb;
  v_next timestamptz; v_candidate timestamptz; v_interval integer;
begin
  if auth.uid() is null then raise exception 'Login is required before donor registration'; end if;
  if public.is_staff() then raise exception 'Staff and admin accounts cannot register as donor accounts'; end if;

  v_birth:=nullif(p_data->>'birth_date','')::date;
  v_last:=nullif(p_data->>'last_donation_date','')::date;
  v_email:=lower(trim(p_data->>'email'));
  v_phone:=public.normalize_phone(p_data->>'phone');
  v_weight:=nullif(p_data->>'weight_kg','')::numeric;
  v_health:=trim(coalesce(p_data->>'health_issues',''));
  v_tattoo:=coalesce(nullif(p_data->>'has_tattoo','')::boolean,false);
  v_piercing:=coalesce(nullif(p_data->>'has_piercing','')::boolean,false);
  v_tattoo_date:=nullif(p_data->>'tattoo_date','')::date;
  v_piercing_date:=nullif(p_data->>'piercing_date','')::date;
  v_screen:=coalesce(p_data->'screening_answers','{}'::jsonb);
  if jsonb_typeof(v_screen) <> 'object' then raise exception 'Detailed donor pre-screen answers are required'; end if;
  v_permanent:=coalesce(v_screen->'permanent_conditions','[]'::jsonb);
  v_review:=coalesce(v_screen->'review_conditions','[]'::jsonb);
  if jsonb_typeof(v_permanent) <> 'array' then v_permanent:='[]'::jsonb; end if;
  if jsonb_typeof(v_review) <> 'array' then v_review:='[]'::jsonb; end if;

  v_current_illness:=coalesce(nullif(v_screen->>'current_illness','')::boolean,false);
  v_antibiotics:=coalesce(nullif(v_screen->>'on_antibiotics','')::boolean,false);
  v_medication:=coalesce(nullif(v_screen->>'medication_current','')::boolean,false);
  v_breastfeeding:=coalesce(nullif(v_screen->>'breastfeeding','')::boolean,false);
  v_acupuncture:=coalesce(nullif(v_screen->>'has_acupuncture','')::boolean,false);
  v_acupuncture_date:=nullif(v_screen->>'acupuncture_date','')::date;
  v_pregnancy:=coalesce(nullif(v_screen->>'pregnancy_status',''),'not_applicable');
  v_alcohol_recent:=coalesce(nullif(v_screen->>'alcohol_last_24h','')::boolean,false);
  v_last_alcohol:=nullif(v_screen->>'last_alcohol_at','')::timestamptz;
  v_nicotine:=coalesce(nullif(v_screen->>'smokes','')::boolean,false);
  v_last_nicotine:=nullif(v_screen->>'last_nicotine_at','')::timestamptz;

  if v_birth is null or v_birth >= current_date then raise exception 'Birth date must be a valid past date'; end if;
  v_age:=extract(year from age(current_date,v_birth))::integer;
  if v_age < 18 or v_age > 65 then raise exception 'BloodCare online screening requires age 18 to 65'; end if;
  if v_weight is null or v_weight < 50 then raise exception 'BloodCare online screening requires a minimum weight of 50 kg'; end if;
  if length(v_health)=0 then raise exception 'Detailed health screening information is required'; end if;
  if v_last is not null and v_last > current_date then raise exception 'Last donation date cannot be in the future'; end if;
  if v_tattoo and v_tattoo_date is null then raise exception 'Enter the date of the most recent tattoo'; end if;
  if v_piercing and v_piercing_date is null then raise exception 'Enter the date of the most recent piercing'; end if;
  if v_acupuncture and v_acupuncture_date is null then raise exception 'Enter the date of the most recent acupuncture'; end if;
  if v_tattoo_date is not null and v_tattoo_date > current_date then raise exception 'Tattoo date cannot be in the future'; end if;
  if v_piercing_date is not null and v_piercing_date > current_date then raise exception 'Piercing date cannot be in the future'; end if;
  if v_acupuncture_date is not null and v_acupuncture_date > current_date then raise exception 'Acupuncture date cannot be in the future'; end if;
  if jsonb_array_length(v_permanent)>0 then
    raise exception 'Your online pre-screen reported a condition that requires direct BloodCare staff guidance before donor registration';
  end if;
  if exists(select 1 from public.donors where lower(email)=v_email and birth_date=v_birth) then
    raise exception 'A donor with this email and birth date is already registered.';
  end if;
  if length(v_phone) < 7 then raise exception 'Enter a valid phone number'; end if;

  select donation_interval_days into v_interval from public.system_settings where id=1;
  v_interval:=coalesce(v_interval,90);

  if v_current_illness then
    v_outcome:='temporarily_deferred';
    v_reasons:=v_reasons||jsonb_build_array('Active illness or infection requires recovery before donation.');
  end if;
  if v_antibiotics then
    v_outcome:='temporarily_deferred';
    v_reasons:=v_reasons||jsonb_build_array('Antibiotic treatment for an infection requires completion and recovery before donation.');
  end if;

  if v_tattoo and v_tattoo_date + interval '1 year' > current_date then
    v_outcome:='temporarily_deferred'; v_candidate:=(v_tattoo_date+interval '1 year')::timestamptz;
    if v_next is null or v_candidate>v_next then v_next:=v_candidate; end if;
    v_reasons:=v_reasons||jsonb_build_array('Tattoo is within the conservative 12-month waiting period.');
  end if;
  if v_piercing and v_piercing_date + interval '1 year' > current_date then
    v_outcome:='temporarily_deferred'; v_candidate:=(v_piercing_date+interval '1 year')::timestamptz;
    if v_next is null or v_candidate>v_next then v_next:=v_candidate; end if;
    v_reasons:=v_reasons||jsonb_build_array('Piercing is within the conservative 12-month waiting period.');
  end if;
  if v_acupuncture and v_acupuncture_date + interval '1 year' > current_date then
    v_outcome:='temporarily_deferred'; v_candidate:=(v_acupuncture_date+interval '1 year')::timestamptz;
    if v_next is null or v_candidate>v_next then v_next:=v_candidate; end if;
    v_reasons:=v_reasons||jsonb_build_array('Acupuncture is within the conservative 12-month waiting period.');
  end if;

  if v_pregnancy='pregnant' then
    v_outcome:='temporarily_deferred'; v_next:=null;
    v_reasons:=v_reasons||jsonb_build_array('Pregnancy requires temporary deferral and later staff clearance.');
  elsif v_pregnancy='recent_birth' then
    v_outcome:='temporarily_deferred'; v_next:=null;
    v_reasons:=v_reasons||jsonb_build_array('Recent childbirth requires postpartum recovery and staff review.');
  end if;

  if v_alcohol_recent then
    if v_last_alcohol is null then raise exception 'Enter the time of the last alcoholic drink'; end if;
    if v_last_alcohol > now() then raise exception 'Alcohol-use time cannot be in the future'; end if;
    v_candidate:=v_last_alcohol+interval '24 hours';
    if v_candidate>now() then
      v_outcome:='temporarily_deferred'; if v_next is not null and v_candidate>v_next then v_next:=v_candidate; elsif v_next is null and v_pregnancy not in ('pregnant','recent_birth') and not v_current_illness and not v_antibiotics then v_next:=v_candidate; end if;
      v_reasons:=v_reasons||jsonb_build_array('Alcohol was consumed within the 24-hour pre-donation waiting period.');
    end if;
  end if;

  if v_nicotine then
    if v_last_nicotine is null then raise exception 'Enter the time of the last cigarette or vape'; end if;
    if v_last_nicotine > now() then raise exception 'Nicotine-use time cannot be in the future'; end if;
    v_candidate:=v_last_nicotine+interval '4 hours';
    if v_candidate>now() then
      v_outcome:='temporarily_deferred'; if v_next is not null and v_candidate>v_next then v_next:=v_candidate; elsif v_next is null and v_pregnancy not in ('pregnant','recent_birth') and not v_current_illness and not v_antibiotics then v_next:=v_candidate; end if;
      v_reasons:=v_reasons||jsonb_build_array('Smoking or vaping was within BloodCare''s 4-hour pre-donation buffer.');
    end if;
  end if;

  if v_last is not null and v_last + v_interval > current_date then
    v_outcome:='temporarily_deferred'; v_candidate:=(v_last+v_interval)::timestamptz;
    if v_next is not null and v_candidate>v_next then v_next:=v_candidate; elsif v_next is null and v_pregnancy not in ('pregnant','recent_birth') and not v_current_illness and not v_antibiotics then v_next:=v_candidate; end if;
    v_reasons:=v_reasons||jsonb_build_array('Previous donation is still within the configured donation interval.');
  end if;

  if jsonb_array_length(v_review)>0 then
    if v_outcome='preliminarily_eligible' then v_outcome:='needs_review'; end if;
    v_reasons:=v_reasons||jsonb_build_array('Reported chronic medical history requires staff or medical review.');
  end if;
  if v_medication then
    if v_outcome='preliminarily_eligible' then v_outcome:='needs_review'; end if;
    v_reasons:=v_reasons||jsonb_build_array('Current medication requires staff review before donation.');
  end if;
  if v_breastfeeding then
    if v_outcome='preliminarily_eligible' then v_outcome:='needs_review'; end if;
    v_reasons:=v_reasons||jsonb_build_array('Breastfeeding requires individual staff review.');
  end if;
  if jsonb_array_length(v_reasons)=0 then
    v_reasons:=jsonb_build_array('No automatic deferral was identified. Final eligibility remains subject to staff screening.');
  end if;

  insert into public.donors(
    auth_user_id,first_name,last_name,email,phone,birth_date,sex,blood_type,last_donation_date,
    barangay,municipality,street,province,notes,weight_kg,health_issues,has_tattoo,tattoo_date,
    has_piercing,piercing_date,drinks_alcohol,smokes,other_habits,pre_screened,status,
    screening_answers,screening_outcome,screening_reasons,screening_next_eligible_at,screening_completed_at
  ) values(
    auth.uid(),trim(p_data->>'first_name'),trim(p_data->>'last_name'),v_email,v_phone,v_birth,
    trim(p_data->>'sex'),trim(p_data->>'blood_type'),v_last,trim(p_data->>'barangay'),
    trim(p_data->>'municipality'),trim(p_data->>'street'),trim(p_data->>'province'),
    nullif(trim(p_data->>'notes'),''),v_weight,v_health,v_tattoo,v_tattoo_date,v_piercing,
    v_piercing_date,coalesce(nullif(p_data->>'drinks_alcohol','')::boolean,false),
    coalesce(nullif(p_data->>'smokes','')::boolean,false),nullif(trim(p_data->>'other_habits'),''),true,'pending',
    v_screen,v_outcome,v_reasons,v_next,now()
  ) returning donor_code into v_code;
  return v_code;
end $$;
revoke all on function public.register_donor(jsonb) from public,anon;
grant execute on function public.register_donor(jsonb) to authenticated;


-- ============================================================
-- Self-service BloodCare profile name update
-- ============================================================
create or replace function public.update_my_profile_name(p_first_name text, p_last_name text default '')
returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  v_uid uuid:=auth.uid();
  v_first text:=trim(coalesce(p_first_name,''));
  v_last text:=trim(coalesce(p_last_name,''));
  v_full text;
begin
  if v_uid is null then raise exception 'Login required'; end if;
  if char_length(v_first)<1 or char_length(v_first)>80 then raise exception 'First name must be between 1 and 80 characters'; end if;
  if char_length(v_last)>80 then raise exception 'Last name must be 80 characters or fewer'; end if;
  v_full:=trim(concat_ws(' ',v_first,nullif(v_last,'')));

  -- A management account may edit its auth display name, but it must never be
  -- linked to or modify a donor identity through this self-service function.
  update auth.users
     set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('full_name',v_full),
         updated_at=now()
   where id=v_uid;

  if not exists(select 1 from public.staff_profiles s where s.id=v_uid and s.active=true) then
    update public.donors
       set first_name=v_first,last_name=v_last,updated_at=now()
     where auth_user_id=v_uid;
  end if;

  return jsonb_build_object('first_name',v_first,'last_name',v_last,'full_name',v_full);
end $$;
grant execute on function public.update_my_profile_name(text,text) to authenticated;

-- ============================================================
-- v18: Admin contact inbox/replies + contact account linkage
-- ============================================================
alter table public.contact_messages add column if not exists auth_user_id uuid;
alter table public.contact_messages add column if not exists source_page text;
alter table public.contact_messages add column if not exists reply_message text;
alter table public.contact_messages add column if not exists replied_at timestamptz;
alter table public.contact_messages add column if not exists replied_by uuid;
alter table public.contact_messages add column if not exists email_delivery_status text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='contact_messages_auth_user_id_fkey'
      and conrelid='public.contact_messages'::regclass
  ) then
    alter table public.contact_messages
      add constraint contact_messages_auth_user_id_fkey
      foreign key(auth_user_id) references auth.users(id) on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='contact_messages_replied_by_fkey'
      and conrelid='public.contact_messages'::regclass
  ) then
    alter table public.contact_messages
      add constraint contact_messages_replied_by_fkey
      foreign key(replied_by) references auth.users(id) on delete set null;
  end if;
end $$;

alter table public.contact_messages drop constraint if exists contact_messages_status_check;
alter table public.contact_messages
  add constraint contact_messages_status_check
  check(status in ('new','read','replied','resolved'));

alter table public.contact_messages drop constraint if exists contact_messages_email_delivery_status_check;
alter table public.contact_messages
  add constraint contact_messages_email_delivery_status_check
  check(email_delivery_status is null or email_delivery_status in ('sent','failed'));

-- Contact messages are an administrator communication inbox.
drop policy if exists "staff contact read" on public.contact_messages;
drop policy if exists "staff contact update" on public.contact_messages;
drop policy if exists "admin contact read" on public.contact_messages;
drop policy if exists "admin contact update" on public.contact_messages;
create policy "admin contact read" on public.contact_messages
  for select to authenticated using (public.is_admin());
create policy "admin contact update" on public.contact_messages
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

grant select,update on table public.contact_messages to authenticated;
notify pgrst, 'reload schema';

-- ============================================================
-- v19: Facility ownership, branch-scoped staff access, and admin oversight
-- ============================================================

-- One facility may be designated as BloodCare's main branch.
alter table public.facilities add column if not exists is_main_branch boolean not null default false;

create or replace function public.keep_single_main_branch()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.is_main_branch then
    update public.facilities set is_main_branch=false,updated_at=now()
    where id<>new.id and is_main_branch=true;
  end if;
  return new;
end $$;

drop trigger if exists facilities_single_main_branch on public.facilities;
create trigger facilities_single_main_branch
before insert or update of is_main_branch on public.facilities
for each row execute function public.keep_single_main_branch();

create unique index if not exists facilities_one_main_branch_idx
on public.facilities((is_main_branch)) where is_main_branch=true;

-- Staff may be assigned to one primary branch and, when needed, additional branches.
create table if not exists public.staff_facility_assignments (
  staff_id uuid not null references public.staff_profiles(id) on delete cascade,
  facility_id uuid not null references public.facilities(id) on delete cascade,
  is_primary boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(staff_id,facility_id)
);
create unique index if not exists staff_facility_one_primary_idx
on public.staff_facility_assignments(staff_id) where is_primary=true;
create index if not exists staff_facility_facility_idx
on public.staff_facility_assignments(facility_id,staff_id);

-- Operational records belong to a branch. Existing branch-aware columns are preserved.
alter table public.donors add column if not exists facility_id uuid references public.facilities(id) on delete set null;
alter table public.inventory_transactions add column if not exists facility_id uuid references public.facilities(id) on delete set null;
alter table public.blood_releases add column if not exists facility_id uuid references public.facilities(id) on delete set null;
create index if not exists donors_facility_idx on public.donors(facility_id,status,created_at desc);
create index if not exists appointments_facility_idx on public.appointments(facility_id,appointment_date,status);
create index if not exists donations_facility_idx on public.donations(facility_id,donation_date desc);
create index if not exists releases_facility_idx on public.blood_releases(facility_id,released_at desc);
create index if not exists inventory_transactions_facility_idx on public.inventory_transactions(facility_id,created_at desc);

-- Ensure an existing deployment has a main branch and place legacy records there.
do $$
declare v_main uuid;
begin
  select id into v_main from public.facilities where is_main_branch=true order by created_at limit 1;
  if v_main is null then
    select id into v_main from public.facilities where active=true order by created_at,id limit 1;
    if v_main is not null then update public.facilities set is_main_branch=true where id=v_main; end if;
  end if;

  if v_main is not null then
    insert into public.staff_facility_assignments(staff_id,facility_id,is_primary,created_by)
    select s.id,v_main,true,null from public.staff_profiles s
    where not exists(select 1 from public.staff_facility_assignments a where a.staff_id=s.id)
    on conflict(staff_id,facility_id) do nothing;

    update public.donors set facility_id=v_main where facility_id is null;
    update public.blood_requests set facility_id=v_main where facility_id is null;
    update public.appointments set facility_id=v_main where facility_id is null;
    update public.donations set facility_id=v_main where facility_id is null;
    update public.blood_units set facility_id=v_main where facility_id is null;

    update public.blood_releases br
       set facility_id=coalesce(r.facility_id,v_main)
      from public.blood_requests r
     where br.request_id=r.id and br.facility_id is null;
    update public.blood_releases set facility_id=v_main where facility_id is null;

    update public.inventory_transactions it
       set facility_id=d.facility_id
      from public.donations d
     where it.facility_id is null and it.donation_id=d.id and d.facility_id is not null;
    update public.inventory_transactions it
       set facility_id=r.facility_id
      from public.blood_requests r
     where it.facility_id is null and it.request_id=r.id and r.facility_id is not null;
    update public.inventory_transactions set facility_id=v_main where facility_id is null;
  end if;
end $$;

create or replace function public.staff_has_facility_access(p_facility uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_admin() or (
    p_facility is not null and exists(
      select 1 from public.staff_facility_assignments a
      join public.staff_profiles s on s.id=a.staff_id
      where a.staff_id=auth.uid() and a.facility_id=p_facility and s.active=true
    )
  )
$$;

grant execute on function public.staff_has_facility_access(uuid) to authenticated;

create or replace function public.my_staff_facilities()
returns table(
  facility_id uuid,
  name text,
  facility_type text,
  district text,
  municipality text,
  province text,
  is_main_branch boolean,
  is_primary boolean
)
language sql stable security definer set search_path=public as $$
  select f.id,f.name,f.facility_type,f.district,f.municipality,f.province,f.is_main_branch,a.is_primary
  from public.staff_facility_assignments a
  join public.staff_profiles s on s.id=a.staff_id and s.active=true
  join public.facilities f on f.id=a.facility_id and f.active=true
  where a.staff_id=auth.uid()
  order by a.is_primary desc,f.name
$$;
revoke all on function public.my_staff_facilities() from public;
grant execute on function public.my_staff_facilities() to authenticated;

create or replace function public.admin_set_staff_facilities(
  p_staff_id uuid,
  p_facility_ids uuid[],
  p_primary_facility uuid
)
returns void language plpgsql security definer set search_path=public as $$
declare v_role text; v_ids uuid[]:=coalesce(p_facility_ids,'{}'::uuid[]); v_id uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  select role into v_role from public.staff_profiles where id=p_staff_id;
  if v_role is null then raise exception 'Staff account not found'; end if;
  if p_primary_facility is null then raise exception 'A primary facility is required'; end if;
  if not (p_primary_facility=any(v_ids)) then v_ids:=array_append(v_ids,p_primary_facility); end if;
  if coalesce(array_length(v_ids,1),0)=0 then raise exception 'Assign at least one facility'; end if;

  foreach v_id in array v_ids loop
    if not exists(select 1 from public.facilities where id=v_id and active=true) then
      raise exception 'Every staff assignment must reference an active facility';
    end if;
  end loop;

  delete from public.staff_facility_assignments where staff_id=p_staff_id;
  insert into public.staff_facility_assignments(staff_id,facility_id,is_primary,created_by)
  select p_staff_id,x,(x=p_primary_facility),auth.uid()
  from (select distinct unnest(v_ids) x) q;
end $$;
revoke all on function public.admin_set_staff_facilities(uuid,uuid[],uuid) from public;
grant execute on function public.admin_set_staff_facilities(uuid,uuid[],uuid) to authenticated;

create or replace function public.admin_update_staff(p_id uuid,p_role text,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_role not in ('staff','admin') then raise exception 'Invalid role'; end if;
  if p_id=auth.uid() and p_active=false then raise exception 'You cannot disable your own account'; end if;
  if p_id=auth.uid() and p_role<>'admin' then raise exception 'You cannot remove your own administrator role'; end if;
  if p_active and not exists(select 1 from public.staff_facility_assignments where staff_id=p_id) then
    raise exception 'Assign at least one facility before enabling this account';
  end if;
  update public.staff_profiles set role=p_role,active=p_active where id=p_id;
  if not found then raise exception 'Staff account not found'; end if;
end $$;
grant execute on function public.admin_update_staff(uuid,text,boolean) to authenticated;

-- New donor records default to the main branch. A user who started from a selected
-- partner facility can change their own branch immediately after registration.
create or replace function public.default_donor_facility()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.facility_id is null then
    select id into new.facility_id from public.facilities
    where is_main_branch=true and active=true order by created_at limit 1;
  end if;
  return new;
end $$;
drop trigger if exists donors_default_facility on public.donors;
create trigger donors_default_facility before insert on public.donors
for each row execute function public.default_donor_facility();

create or replace function public.set_my_donor_facility(p_facility_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if public.is_staff() then raise exception 'Management accounts cannot use donor self-service'; end if;
  if not exists(select 1 from public.facilities where id=p_facility_id and active=true) then raise exception 'Facility not found or inactive'; end if;
  update public.donors set facility_id=p_facility_id,updated_at=now() where auth_user_id=auth.uid();
  if not found then raise exception 'Linked donor profile not found'; end if;
end $$;
revoke all on function public.set_my_donor_facility(uuid) from public;
grant execute on function public.set_my_donor_facility(uuid) to authenticated;

-- Branch-scoped RLS. Admin remains system-wide; staff see only assigned branches.
alter table public.staff_facility_assignments enable row level security;
drop policy if exists "staff assignment self read" on public.staff_facility_assignments;
drop policy if exists "admin assignment read" on public.staff_facility_assignments;
drop policy if exists "admin assignment insert" on public.staff_facility_assignments;
drop policy if exists "admin assignment update" on public.staff_facility_assignments;
drop policy if exists "admin assignment delete" on public.staff_facility_assignments;
create policy "staff assignment self read" on public.staff_facility_assignments
  for select to authenticated using(staff_id=auth.uid() or public.is_admin());
create policy "admin assignment insert" on public.staff_facility_assignments
  for insert to authenticated with check(public.is_admin());
create policy "admin assignment update" on public.staff_facility_assignments
  for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin assignment delete" on public.staff_facility_assignments
  for delete to authenticated using(public.is_admin());
grant select,insert,update,delete on public.staff_facility_assignments to authenticated;

drop policy if exists "staff donors read" on public.donors;
drop policy if exists "branch donors read" on public.donors;
create policy "branch donors read" on public.donors for select to authenticated
  using(public.is_admin() or public.staff_has_facility_access(facility_id));

drop policy if exists "staff requests read" on public.blood_requests;
drop policy if exists "branch requests read" on public.blood_requests;
create policy "branch requests read" on public.blood_requests for select to authenticated
  using(public.is_admin() or public.staff_has_facility_access(facility_id));

drop policy if exists "staff appointments read" on public.appointments;
drop policy if exists "branch appointments read" on public.appointments;
create policy "branch appointments read" on public.appointments for select to authenticated
  using(public.is_admin() or public.staff_has_facility_access(facility_id));

drop policy if exists "staff donations read" on public.donations;
drop policy if exists "branch donations read" on public.donations;
create policy "branch donations read" on public.donations for select to authenticated
  using(public.is_admin() or public.staff_has_facility_access(facility_id));

drop policy if exists "staff units read" on public.blood_units;
drop policy if exists "branch units read" on public.blood_units;
create policy "branch units read" on public.blood_units for select to authenticated
  using(public.is_admin() or public.staff_has_facility_access(facility_id));

drop policy if exists "staff releases read" on public.blood_releases;
drop policy if exists "branch releases read" on public.blood_releases;
create policy "branch releases read" on public.blood_releases for select to authenticated
  using(public.is_admin() or public.staff_has_facility_access(facility_id));

drop policy if exists "staff inventory movements read" on public.inventory_transactions;
drop policy if exists "branch inventory movements read" on public.inventory_transactions;
create policy "branch inventory movements read" on public.inventory_transactions for select to authenticated
  using(public.is_admin() or public.staff_has_facility_access(facility_id));

-- Branch-safe staff workflow RPCs. SECURITY DEFINER functions explicitly verify access.
create or replace function public.set_donor_status(p_donor_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_facility uuid;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_status not in ('pending','eligible','deferred','inactive') then raise exception 'Invalid donor status'; end if;
  select facility_id into v_facility from public.donors where id=p_donor_id;
  if not found then raise exception 'Donor not found'; end if;
  if not public.staff_has_facility_access(v_facility) then raise exception 'This donor belongs to another facility'; end if;
  update public.donors set status=p_status,review_notes=p_notes,reviewed_by=auth.uid(),updated_at=now() where id=p_donor_id;
end $$;

create or replace function public.update_donor_contact(p_donor_id uuid,p_data jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_facility uuid;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  select facility_id into v_facility from public.donors where id=p_donor_id;
  if not found then raise exception 'Donor not found'; end if;
  if not public.staff_has_facility_access(v_facility) then raise exception 'This donor belongs to another facility'; end if;
  update public.donors set
    email=lower(trim(p_data->>'email')),phone=trim(p_data->>'phone'),street=trim(p_data->>'street'),
    barangay=trim(p_data->>'barangay'),municipality=trim(p_data->>'municipality'),province=trim(p_data->>'province'),updated_at=now()
  where id=p_donor_id;
end $$;

create or replace function public.reserve_blood_for_request(p_request_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_ids uuid[]; v_have integer; v_need integer; v_balance integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  perform public.refresh_expired_units();
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if r.facility_id is null or not public.staff_has_facility_access(r.facility_id) then raise exception 'This request belongs to another facility'; end if;

  select count(*)::integer into v_have from public.blood_units where request_id=r.id and status='reserved';
  v_need:=r.bags-v_have;
  if v_need>0 then
    select array_agg(id) into v_ids from (
      select id from public.blood_units
      where blood_type=r.blood_type and status='available' and facility_id=r.facility_id
        and (expiry_date is null or expiry_date>=current_date)
      order by expiry_date nulls last,collection_date nulls last,created_at
      limit v_need for update skip locked
    ) q;
    if coalesce(array_length(v_ids,1),0)<v_need then raise exception 'Insufficient unexpired inventory at this facility: % more bag(s) needed',v_need; end if;
    update public.blood_units set status='reserved',request_id=r.id,updated_at=now() where id=any(v_ids);
    update public.blood_inventory set bags_available=bags_available-v_need,updated_at=now() where blood_type=r.blood_type returning bags_available into v_balance;
    insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,request_id,performed_by,facility_id)
      values(r.blood_type,-v_need,v_balance,'reservation','Reserved for '||r.request_code,r.id,auth.uid(),r.facility_id);
  end if;
  update public.blood_requests set reserved_at=coalesce(reserved_at,now()),updated_at=now() where id=r.id;
  return r.bags;
end $$;

create or replace function public.release_request_reservation(p_request_id uuid,p_reason text default 'Reservation released')
returns integer language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_qty integer; v_balance integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if r.facility_id is null or not public.staff_has_facility_access(r.facility_id) then raise exception 'This request belongs to another facility'; end if;
  select count(*)::integer into v_qty from public.blood_units where request_id=r.id and status='reserved';
  if v_qty>0 then
    update public.blood_units set status='available',request_id=null,updated_at=now() where request_id=r.id and status='reserved';
    update public.blood_inventory set bags_available=bags_available+v_qty,updated_at=now() where blood_type=r.blood_type returning bags_available into v_balance;
    insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,request_id,performed_by,facility_id)
      values(r.blood_type,v_qty,v_balance,'reservation_release',coalesce(nullif(trim(p_reason),''),'Reservation released'),r.id,auth.uid(),r.facility_id);
  end if;
  update public.blood_requests set reserved_at=null,updated_at=now() where id=r.id;
  return v_qty;
end $$;

create or replace function public.update_request_status(p_request_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_facility uuid;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_status not in ('pending','under_review','approved','ready_for_release','rejected','cancelled') then raise exception 'Use Release Blood to complete a request'; end if;
  select facility_id into v_facility from public.blood_requests where id=p_request_id;
  if not found then raise exception 'Request not found'; end if;
  if not public.staff_has_facility_access(v_facility) then raise exception 'This request belongs to another facility'; end if;
  if p_status in ('approved','ready_for_release') then perform public.reserve_blood_for_request(p_request_id);
  elsif p_status in ('pending','under_review','rejected','cancelled') then perform public.release_request_reservation(p_request_id,'Status changed to '||replace(p_status,'_',' ')); end if;
  update public.blood_requests set status=p_status,staff_notes=p_notes,processed_by=auth.uid(),updated_at=now() where id=p_request_id;
end $$;

create or replace function public.release_blood_request(p_request_id uuid,p_notes text default null)
returns text language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_unit_ids uuid[]; locked_count integer; v_release text;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  perform public.refresh_expired_units();
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if r.facility_id is null or not public.staff_has_facility_access(r.facility_id) then raise exception 'This request belongs to another facility'; end if;
  if r.status not in ('approved','ready_for_release') then raise exception 'Request must be approved before blood can be released'; end if;
  perform public.reserve_blood_for_request(r.id);
  select array_agg(id) into v_unit_ids from (
    select id from public.blood_units where request_id=r.id and status='reserved' and facility_id=r.facility_id
    order by expiry_date nulls last,collection_date nulls last,created_at limit r.bags for update
  ) q;
  locked_count:=coalesce(array_length(v_unit_ids,1),0);
  if locked_count<r.bags then raise exception 'Reserved inventory is incomplete'; end if;
  update public.blood_units set status='released',updated_at=now() where id=any(v_unit_ids);
  insert into public.blood_releases(request_id,blood_type,bags,notes,released_by,facility_id)
    values(r.id,r.blood_type,r.bags,p_notes,auth.uid(),r.facility_id) returning release_code into v_release;
  update public.blood_requests set status='completed',reserved_at=null,staff_notes=coalesce(p_notes,staff_notes),processed_by=auth.uid(),updated_at=now() where id=r.id;
  return v_release;
end $$;

create or replace function public.update_appointment_status(p_appointment_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_facility uuid;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_status not in ('requested','confirmed','checked_in','completed','cancelled','no_show') then raise exception 'Invalid appointment status'; end if;
  select facility_id into v_facility from public.appointments where id=p_appointment_id;
  if not found then raise exception 'Appointment not found'; end if;
  if not public.staff_has_facility_access(v_facility) then raise exception 'This appointment belongs to another facility'; end if;
  update public.appointments set status=p_status,staff_notes=p_notes,processed_by=auth.uid(),updated_at=now() where id=p_appointment_id;
end $$;

create or replace function public.record_donation_v3(
  p_donor_code text,p_bags integer,p_donation_date date,p_facility_id uuid,
  p_appointment_id uuid default null,p_expiry_date date default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_donor public.donors%rowtype; v_donation_id uuid; v_code text; v_balance integer; v_site text; i integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if not public.staff_has_facility_access(p_facility_id) then raise exception 'You are not assigned to this facility'; end if;
  if p_bags < 1 or p_bags > 10 then raise exception 'Invalid bag count'; end if;
  if p_donation_date is null or p_donation_date > current_date then raise exception 'Donation date cannot be in the future'; end if;
  if p_expiry_date is not null and p_expiry_date < p_donation_date then raise exception 'Expiry date cannot be earlier than the donation date'; end if;
  select name into v_site from public.facilities where id=p_facility_id and active=true;
  if v_site is null then raise exception 'Select an active donation facility'; end if;
  select * into v_donor from public.donors where donor_code=upper(trim(p_donor_code)) for update;
  if not found then raise exception 'Donor code not found'; end if;
  if v_donor.status <> 'eligible' then raise exception 'Donor must be marked eligible before a donation can be recorded'; end if;
  if p_appointment_id is not null and not exists(
    select 1 from public.appointments where id=p_appointment_id and facility_id=p_facility_id and (donor_id=v_donor.id or donor_id is null)
  ) then raise exception 'Appointment does not match this donor and facility'; end if;

  insert into public.donations(donor_id,donor_code,blood_type,bags,donation_date,donation_site,facility_id,appointment_id,expiry_date,recorded_by)
  values(v_donor.id,v_donor.donor_code,v_donor.blood_type,p_bags,p_donation_date,v_site,p_facility_id,p_appointment_id,p_expiry_date,auth.uid())
  returning id,donation_code into v_donation_id,v_code;
  for i in 1..p_bags loop
    insert into public.blood_units(donation_id,donor_id,blood_type,collection_date,expiry_date,source,status,facility_id)
    values(v_donation_id,v_donor.id,v_donor.blood_type,p_donation_date,p_expiry_date,'donation','available',p_facility_id);
  end loop;
  update public.blood_inventory set bags_available=bags_available+p_bags,updated_at=now() where blood_type=v_donor.blood_type returning bags_available into v_balance;
  insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,donation_id,performed_by,facility_id)
  values(v_donor.blood_type,p_bags,v_balance,'donation','Donation '||v_code||' at '||v_site,v_donation_id,auth.uid(),p_facility_id);
  update public.donors set last_donation_date=p_donation_date,updated_at=now() where id=v_donor.id;
  if p_appointment_id is not null then update public.appointments set donor_id=v_donor.id,status='completed',processed_by=auth.uid(),updated_at=now() where id=p_appointment_id; end if;
  return v_code;
end $$;

create or replace function public.set_blood_unit_facility(p_unit_id uuid,p_facility_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_current uuid;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if not public.staff_has_facility_access(p_facility_id) then raise exception 'You are not assigned to the destination facility'; end if;
  select facility_id into v_current from public.blood_units where id=p_unit_id and status='available';
  if not found then raise exception 'Only available blood units can be reassigned to a facility'; end if;
  if v_current is not null and not public.staff_has_facility_access(v_current) then raise exception 'You cannot move stock from another facility'; end if;
  update public.blood_units set facility_id=p_facility_id,updated_at=now() where id=p_unit_id;
end $$;

create or replace function public.adjust_facility_inventory(
  p_facility_id uuid,p_blood_type text,p_new_quantity integer,p_reason text
) returns integer language plpgsql security definer set search_path=public as $$
declare v_old integer; v_delta integer; v_type text; v_balance integer; i integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if not public.staff_has_facility_access(p_facility_id) then raise exception 'You are not assigned to this facility'; end if;
  if not exists(select 1 from public.facilities where id=p_facility_id and active=true) then raise exception 'Facility not found or inactive'; end if;
  if p_blood_type not in ('A+','A-','B+','B-','AB+','AB-','O+','O-') then raise exception 'Invalid blood type'; end if;
  if p_new_quantity<0 then raise exception 'Quantity cannot be negative'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Adjustment reason is required'; end if;

  perform public.refresh_expired_units();
  select count(*)::integer into v_old from public.blood_units
  where facility_id=p_facility_id and blood_type=p_blood_type and status='available' and (expiry_date is null or expiry_date>=current_date);
  v_delta:=p_new_quantity-v_old;
  if v_delta=0 then return v_old; end if;

  if v_delta>0 then
    for i in 1..v_delta loop
      insert into public.blood_units(blood_type,source,status,facility_id)
      values(p_blood_type,'manual / transfer in','available',p_facility_id);
    end loop;
    v_type:='transfer_in';
  else
    if (select count(*) from public.blood_units where facility_id=p_facility_id and blood_type=p_blood_type and status='available')<abs(v_delta) then
      raise exception 'Not enough available units at this facility to remove';
    end if;
    update public.blood_units set status=case when lower(p_reason) like '%expir%' then 'expired' else 'discarded' end,updated_at=now()
    where id in (
      select id from public.blood_units where facility_id=p_facility_id and blood_type=p_blood_type and status='available'
      order by expiry_date nulls last,created_at limit abs(v_delta)
    );
    v_type:=case when lower(p_reason) like '%expir%' then 'expired' else 'adjustment' end;
  end if;

  update public.blood_inventory set bags_available=greatest(0,bags_available+v_delta),updated_at=now()
  where blood_type=p_blood_type returning bags_available into v_balance;
  insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,performed_by,facility_id)
  values(p_blood_type,v_delta,v_balance,v_type,p_reason,auth.uid(),p_facility_id);
  return p_new_quantity;
end $$;

revoke all on function public.adjust_facility_inventory(uuid,text,integer,text) from public;
grant execute on function public.adjust_facility_inventory(uuid,text,integer,text) to authenticated;

-- Keep function execution grants explicit after replacements.
grant execute on function public.set_donor_status(uuid,text,text) to authenticated;
grant execute on function public.update_donor_contact(uuid,jsonb) to authenticated;
grant execute on function public.reserve_blood_for_request(uuid) to authenticated;
grant execute on function public.release_request_reservation(uuid,text) to authenticated;
grant execute on function public.update_request_status(uuid,text,text) to authenticated;
grant execute on function public.release_blood_request(uuid,text) to authenticated;
grant execute on function public.update_appointment_status(uuid,text,text) to authenticated;
grant execute on function public.record_donation_v3(text,integer,date,uuid,uuid,date) to authenticated;
grant execute on function public.set_blood_unit_facility(uuid,uuid) to authenticated;

notify pgrst, 'reload schema';

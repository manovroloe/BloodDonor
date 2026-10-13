-- BloodCare current full schema
-- Safe to run after the original BloodCare schema. Existing records are preserved.
-- Run this entire file in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- ============================================================
-- Core profiles and helpers
-- ============================================================
create table if not exists public.staff_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'staff',
  created_at timestamptz not null default now()
);
alter table public.staff_profiles add column if not exists email text;
alter table public.staff_profiles add column if not exists active boolean not null default true;
update public.staff_profiles sp set email=u.email from auth.users u where sp.id=u.id and sp.email is null;
alter table public.staff_profiles drop constraint if exists staff_profiles_role_check;
alter table public.staff_profiles add constraint staff_profiles_role_check check (role in ('staff','admin'));

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.staff_profiles where id=auth.uid() and active=true)
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.staff_profiles where id=auth.uid() and active=true and role='admin')
$$;

-- ============================================================
-- Donors
-- ============================================================
create table if not exists public.donors (
  id uuid primary key default gen_random_uuid(),
  donor_code text unique,
  first_name text not null,
  last_name text not null,
  email text not null,
  phone text not null,
  birth_date date not null,
  sex text not null,
  blood_type text not null,
  last_donation_date date,
  barangay text not null,
  municipality text not null,
  street text not null,
  province text not null,
  notes text,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);
alter table public.donors add column if not exists updated_at timestamptz not null default now();
alter table public.donors add column if not exists reviewed_by uuid references auth.users(id);
alter table public.donors add column if not exists review_notes text;
alter table public.donors drop constraint if exists donors_blood_type_check;
alter table public.donors add constraint donors_blood_type_check check (blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-'));
alter table public.donors drop constraint if exists donors_status_check;
alter table public.donors add constraint donors_status_check check(status in ('pending','eligible','deferred','inactive'));

create sequence if not exists public.donor_code_seq start 1;
create or replace function public.set_donor_code() returns trigger language plpgsql as $$
begin
  if new.donor_code is null then new.donor_code := 'DNR-'||lpad(nextval('public.donor_code_seq')::text,6,'0'); end if;
  return new;
end $$;
drop trigger if exists donors_code_trigger on public.donors;
create trigger donors_code_trigger before insert on public.donors for each row execute function public.set_donor_code();

-- ============================================================
-- Blood requests
-- ============================================================
create table if not exists public.blood_requests (
  id uuid primary key default gen_random_uuid(),
  patient_name text not null,
  requester_name text not null,
  email text not null,
  phone text not null,
  blood_type text not null,
  bags integer not null,
  hospital text not null,
  date_needed date not null,
  reason text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.blood_requests add column if not exists request_code text unique;
alter table public.blood_requests add column if not exists processed_by uuid references auth.users(id);
alter table public.blood_requests add column if not exists staff_notes text;
alter table public.blood_requests drop constraint if exists blood_requests_blood_type_check;
alter table public.blood_requests add constraint blood_requests_blood_type_check check (blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-'));
alter table public.blood_requests drop constraint if exists blood_requests_bags_check;
alter table public.blood_requests add constraint blood_requests_bags_check check(bags between 1 and 20);
alter table public.blood_requests drop constraint if exists blood_requests_status_check;
update public.blood_requests set status='completed' where status='fulfilled';
alter table public.blood_requests add constraint blood_requests_status_check check(status in ('pending','under_review','approved','ready_for_release','completed','rejected','cancelled'));

create sequence if not exists public.request_code_seq start 1;
create or replace function public.set_request_code() returns trigger language plpgsql as $$
begin
  if new.request_code is null then new.request_code := 'REQ-'||lpad(nextval('public.request_code_seq')::text,6,'0'); end if;
  return new;
end $$;
drop trigger if exists request_code_trigger on public.blood_requests;
create trigger request_code_trigger before insert on public.blood_requests for each row execute function public.set_request_code();
update public.blood_requests set request_code='REQ-'||lpad(nextval('public.request_code_seq')::text,6,'0') where request_code is null;

-- ============================================================
-- Appointments
-- ============================================================
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text not null,
  blood_type text not null,
  appointment_date date not null,
  appointment_time time not null,
  location text not null,
  status text not null default 'requested',
  created_at timestamptz not null default now()
);
alter table public.appointments add column if not exists appointment_code text unique;
alter table public.appointments add column if not exists donor_id uuid references public.donors(id) on delete set null;
alter table public.appointments add column if not exists processed_by uuid references auth.users(id);
alter table public.appointments add column if not exists staff_notes text;
alter table public.appointments add column if not exists updated_at timestamptz not null default now();
alter table public.appointments alter column status set default 'requested';
alter table public.appointments drop constraint if exists appointments_blood_type_check;
alter table public.appointments add constraint appointments_blood_type_check check (blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-'));
alter table public.appointments drop constraint if exists appointments_status_check;
update public.appointments set status='requested' where status='pending';
alter table public.appointments add constraint appointments_status_check check(status in ('requested','confirmed','checked_in','completed','cancelled','no_show'));

create sequence if not exists public.appointment_code_seq start 1;
create or replace function public.set_appointment_code() returns trigger language plpgsql as $$
begin
  if new.appointment_code is null then new.appointment_code := 'APT-'||lpad(nextval('public.appointment_code_seq')::text,6,'0'); end if;
  return new;
end $$;
drop trigger if exists appointment_code_trigger on public.appointments;
create trigger appointment_code_trigger before insert on public.appointments for each row execute function public.set_appointment_code();
update public.appointments set appointment_code='APT-'||lpad(nextval('public.appointment_code_seq')::text,6,'0') where appointment_code is null;

-- ============================================================
-- Donations, units, inventory, releases and movements
-- ============================================================
create table if not exists public.blood_inventory (
  blood_type text primary key,
  bags_available integer not null default 0,
  reorder_level integer not null default 5,
  updated_at timestamptz not null default now()
);
alter table public.blood_inventory drop constraint if exists blood_inventory_blood_type_check;
alter table public.blood_inventory add constraint blood_inventory_blood_type_check check (blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-'));
alter table public.blood_inventory drop constraint if exists blood_inventory_bags_available_check;
alter table public.blood_inventory add constraint blood_inventory_bags_available_check check(bags_available>=0);
alter table public.blood_inventory drop constraint if exists blood_inventory_reorder_level_check;
alter table public.blood_inventory add constraint blood_inventory_reorder_level_check check(reorder_level>=0);
insert into public.blood_inventory(blood_type,bags_available) values
('A+',0),('A-',0),('B+',0),('B-',0),('AB+',0),('AB-',0),('O+',0),('O-',0) on conflict do nothing;

create table if not exists public.donations (
  id uuid primary key default gen_random_uuid(),
  donor_code text not null,
  blood_type text not null,
  bags integer not null,
  donation_date date not null,
  donation_site text not null,
  recorded_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.donations add column if not exists donation_code text unique;
alter table public.donations add column if not exists donor_id uuid references public.donors(id) on delete set null;
alter table public.donations add column if not exists appointment_id uuid references public.appointments(id) on delete set null;
alter table public.donations add column if not exists expiry_date date;
alter table public.donations drop constraint if exists donations_blood_type_check;
alter table public.donations add constraint donations_blood_type_check check (blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-'));
alter table public.donations drop constraint if exists donations_bags_check;
alter table public.donations add constraint donations_bags_check check(bags between 1 and 10);

create sequence if not exists public.donation_code_seq start 1;
create or replace function public.set_donation_code() returns trigger language plpgsql as $$
begin
  if new.donation_code is null then new.donation_code := 'DNT-'||lpad(nextval('public.donation_code_seq')::text,6,'0'); end if;
  return new;
end $$;
drop trigger if exists donation_code_trigger on public.donations;
create trigger donation_code_trigger before insert on public.donations for each row execute function public.set_donation_code();
update public.donations set donation_code='DNT-'||lpad(nextval('public.donation_code_seq')::text,6,'0') where donation_code is null;
update public.donations d set donor_id=x.id from public.donors x where d.donor_id is null and d.donor_code=x.donor_code;

create table if not exists public.blood_units (
  id uuid primary key default gen_random_uuid(),
  unit_code text unique,
  donation_id uuid references public.donations(id) on delete set null,
  donor_id uuid references public.donors(id) on delete set null,
  blood_type text not null check (blood_type in ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
  collection_date date,
  expiry_date date,
  source text not null default 'donation',
  status text not null default 'available' check(status in ('available','reserved','released','expired','discarded','transferred')),
  request_id uuid references public.blood_requests(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create sequence if not exists public.unit_code_seq start 1;
create or replace function public.set_unit_code() returns trigger language plpgsql as $$
begin
  if new.unit_code is null then new.unit_code := 'UNIT-'||lpad(nextval('public.unit_code_seq')::text,7,'0'); end if;
  return new;
end $$;
drop trigger if exists unit_code_trigger on public.blood_units;
create trigger unit_code_trigger before insert on public.blood_units for each row execute function public.set_unit_code();

create table if not exists public.blood_releases (
  id uuid primary key default gen_random_uuid(),
  release_code text unique,
  request_id uuid not null references public.blood_requests(id) on delete restrict,
  blood_type text not null,
  bags integer not null check(bags>0),
  notes text,
  released_by uuid references auth.users(id),
  released_at timestamptz not null default now()
);
create sequence if not exists public.release_code_seq start 1;
create or replace function public.set_release_code() returns trigger language plpgsql as $$
begin
  if new.release_code is null then new.release_code := 'REL-'||lpad(nextval('public.release_code_seq')::text,6,'0'); end if;
  return new;
end $$;
drop trigger if exists release_code_trigger on public.blood_releases;
create trigger release_code_trigger before insert on public.blood_releases for each row execute function public.set_release_code();

create table if not exists public.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  blood_type text not null,
  quantity_change integer not null check(quantity_change<>0),
  balance_after integer not null check(balance_after>=0),
  transaction_type text not null check(transaction_type in ('donation','release','adjustment','expired','discarded','transfer_in','transfer_out')),
  reason text,
  donation_id uuid references public.donations(id) on delete set null,
  request_id uuid references public.blood_requests(id) on delete set null,
  performed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- Seed unit rows for previous donation records. These are marked as migration units.
insert into public.blood_units(donation_id,donor_id,blood_type,collection_date,expiry_date,source,status)
select d.id,d.donor_id,d.blood_type,d.donation_date,d.expiry_date,'legacy donation','available'
from public.donations d
cross join lateral generate_series(1,d.bags) g
where not exists(select 1 from public.blood_units u where u.donation_id=d.id);

-- Reconcile previous inventory totals with generated units using migration stock rows.
do $$
declare r record; available_count integer; deficit integer;
begin
  for r in select * from public.blood_inventory loop
    select count(*) into available_count from public.blood_units where blood_type=r.blood_type and status='available';
    if r.bags_available > available_count then
      deficit := r.bags_available - available_count;
      insert into public.blood_units(blood_type,source,status)
      select r.blood_type,'legacy inventory','available' from generate_series(1,deficit);
    elsif r.bags_available < available_count then
      update public.blood_units set status='transferred',updated_at=now()
      where id in (
        select id from public.blood_units where blood_type=r.blood_type and status='available'
        order by created_at limit (available_count-r.bags_available)
      );
    end if;
  end loop;
end $$;

-- ============================================================
-- Content, facilities and audit
-- ============================================================
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  published boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.announcements add column if not exists updated_at timestamptz not null default now();
alter table public.announcements add column if not exists image_url text;

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  event_date date not null,
  location text not null,
  image_url text,
  published boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.events add column if not exists event_time time;
alter table public.events add column if not exists contact_person text;
alter table public.events add column if not exists latitude numeric(9,6);
alter table public.events add column if not exists longitude numeric(9,6);
alter table public.events add column if not exists updated_at timestamptz not null default now();

create table if not exists public.facilities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  facility_type text not null default 'Donation Center' check(facility_type in ('Donation Center','Hospital','Clinic','Evacuation Center','Partner Facility')),
  address text not null,
  barangay text,
  municipality text,
  province text,
  phone text,
  operating_hours text,
  services text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated by default as identity primary key,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  performed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.audit_row_change() returns trigger
language plpgsql security definer set search_path=public as $$
declare row_id text; payload jsonb;
begin
  row_id := coalesce((to_jsonb(new)->>'id'),(to_jsonb(old)->>'id'));
  payload := case when tg_op='DELETE' then jsonb_build_object('old',to_jsonb(old))
                  when tg_op='UPDATE' then jsonb_build_object('old',to_jsonb(old),'new',to_jsonb(new))
                  else jsonb_build_object('new',to_jsonb(new)) end;
  insert into public.audit_logs(action,entity_type,entity_id,details,performed_by)
  values(lower(tg_op),tg_table_name,row_id,payload,auth.uid());
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

-- Keep one trigger per auditable table.
do $$
declare t text;
begin
  foreach t in array array['staff_profiles','donors','blood_requests','appointments','donations','blood_units','blood_releases','inventory_transactions','announcements','events','facilities'] loop
    execute format('drop trigger if exists %I on public.%I','audit_'||t,t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_row_change()','audit_'||t,t);
  end loop;
end $$;

drop view if exists public.donation_records_public;

-- ============================================================
-- Public submission / tracking RPCs
-- ============================================================
create or replace function public.register_donor(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare v_code text;
begin
  insert into public.donors(first_name,last_name,email,phone,birth_date,sex,blood_type,last_donation_date,barangay,municipality,street,province,notes)
  values(trim(p_data->>'first_name'),trim(p_data->>'last_name'),lower(trim(p_data->>'email')),trim(p_data->>'phone'),
         nullif(p_data->>'birth_date','')::date,trim(p_data->>'sex'),trim(p_data->>'blood_type'),nullif(p_data->>'last_donation_date','')::date,
         trim(p_data->>'barangay'),trim(p_data->>'municipality'),trim(p_data->>'street'),trim(p_data->>'province'),nullif(trim(p_data->>'notes'),''))
  returning donor_code into v_code;
  return v_code;
end $$;

grant execute on function public.register_donor(jsonb) to anon,authenticated;

create or replace function public.submit_blood_request(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare v_code text;
begin
  insert into public.blood_requests(patient_name,requester_name,email,phone,blood_type,bags,hospital,date_needed,reason,status)
  values(trim(p_data->>'patient_name'),trim(p_data->>'requester_name'),lower(trim(p_data->>'email')),trim(p_data->>'phone'),
         trim(p_data->>'blood_type'),(p_data->>'bags')::integer,trim(p_data->>'hospital'),(p_data->>'date_needed')::date,trim(p_data->>'reason'),'pending')
  returning request_code into v_code;
  return v_code;
end $$;
grant execute on function public.submit_blood_request(jsonb) to anon,authenticated;

create or replace function public.submit_appointment(p_data jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare v_code text; v_donor public.donors%rowtype; v_donor_id uuid; v_type text;
begin
  if nullif(trim(p_data->>'donor_code'),'') is not null then
    select * into v_donor from public.donors where donor_code=upper(trim(p_data->>'donor_code'));
    if not found then raise exception 'Donor code not found'; end if;
    v_donor_id := v_donor.id; v_type := v_donor.blood_type;
  else
    v_type := trim(p_data->>'blood_type');
  end if;
  insert into public.appointments(full_name,email,phone,blood_type,appointment_date,appointment_time,location,donor_id,status)
  values(trim(p_data->>'full_name'),lower(trim(p_data->>'email')),trim(p_data->>'phone'),v_type,
         (p_data->>'appointment_date')::date,(p_data->>'appointment_time')::time,trim(p_data->>'location'),v_donor_id,'requested')
  returning appointment_code into v_code;
  return v_code;
end $$;
grant execute on function public.submit_appointment(jsonb) to anon,authenticated;

create or replace function public.public_track(p_reference text,p_email text)
returns table(reference text,kind text,status text,summary text,updated_at timestamptz)
language plpgsql security definer set search_path=public as $$
begin
  return query
  select r.request_code,'Blood Request'::text,r.status,
         r.blood_type||' • '||r.bags||' bag(s) • '||r.hospital,r.updated_at
  from public.blood_requests r where upper(r.request_code)=upper(trim(p_reference)) and lower(r.email)=lower(trim(p_email))
  union all
  select a.appointment_code,'Appointment'::text,a.status,
         a.blood_type||' • '||a.location||' • '||a.appointment_date::text,a.updated_at
  from public.appointments a where upper(a.appointment_code)=upper(trim(p_reference)) and lower(a.email)=lower(trim(p_email))
  union all
  select d.donor_code,'Donor Registration'::text,d.status,
         d.first_name||' '||d.last_name||' • '||d.blood_type,d.updated_at
  from public.donors d where upper(d.donor_code)=upper(trim(p_reference)) and lower(d.email)=lower(trim(p_email));
end $$;
grant execute on function public.public_track(text,text) to anon,authenticated;

create or replace function public.public_donation_history(p_donor_code text,p_email text)
returns table(donation_code text,donation_date date,blood_type text,bags integer,donation_site text)
language sql security definer set search_path=public as $$
  select x.donation_code,x.donation_date,x.blood_type,x.bags,x.donation_site
  from public.donations x join public.donors d on d.id=x.donor_id
  where upper(d.donor_code)=upper(trim(p_donor_code)) and lower(d.email)=lower(trim(p_email))
  order by x.donation_date desc;
$$;
grant execute on function public.public_donation_history(text,text) to anon,authenticated;

create or replace function public.public_stats()
returns jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'registered_donors',(select count(*) from public.donors),
    'available_bags',(select coalesce(sum(bags_available),0) from public.blood_inventory)
  );
$$;
grant execute on function public.public_stats() to anon,authenticated;



-- ============================================================
-- Private donor profile RPC
-- Requires donor code + registered email and returns only that donor's
-- profile, linked appointments, and verified donation history.
-- ============================================================
create or replace function public.public_donor_profile(p_donor_code text,p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_donor public.donors%rowtype; v_result jsonb;
begin
  select * into v_donor
  from public.donors
  where upper(donor_code)=upper(trim(p_donor_code))
    and lower(email)=lower(trim(p_email));
  if not found then return null; end if;

  select jsonb_build_object(
    'profile',jsonb_build_object(
      'donor_code',v_donor.donor_code,
      'first_name',v_donor.first_name,
      'last_name',v_donor.last_name,
      'email',v_donor.email,
      'phone',v_donor.phone,
      'birth_date',v_donor.birth_date,
      'sex',v_donor.sex,
      'blood_type',v_donor.blood_type,
      'last_donation_date',v_donor.last_donation_date,
      'barangay',v_donor.barangay,
      'municipality',v_donor.municipality,
      'street',v_donor.street,
      'province',v_donor.province,
      'status',v_donor.status,
      'created_at',v_donor.created_at,
      'updated_at',v_donor.updated_at
    ),
    'appointments',coalesce((
      select jsonb_agg(jsonb_build_object(
        'appointment_code',a.appointment_code,
        'appointment_date',a.appointment_date,
        'appointment_time',a.appointment_time,
        'location',a.location,
        'status',a.status
      ) order by a.appointment_date desc,a.appointment_time desc)
      from public.appointments a where a.donor_id=v_donor.id
    ),'[]'::jsonb),
    'donations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'donation_code',d.donation_code,
        'donation_date',d.donation_date,
        'blood_type',d.blood_type,
        'bags',d.bags,
        'donation_site',d.donation_site
      ) order by d.donation_date desc)
      from public.donations d where d.donor_id=v_donor.id
    ),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.public_donor_profile(text,text) from public;
grant execute on function public.public_donor_profile(text,text) to anon,authenticated;

-- ============================================================
-- Staff workflow RPCs
-- ============================================================
create or replace function public.set_donor_status(p_donor_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_status not in ('pending','eligible','deferred','inactive') then raise exception 'Invalid donor status'; end if;
  update public.donors set status=p_status,review_notes=p_notes,reviewed_by=auth.uid(),updated_at=now() where id=p_donor_id;
  if not found then raise exception 'Donor not found'; end if;
end $$;
grant execute on function public.set_donor_status(uuid,text,text) to authenticated;

create or replace function public.update_donor_contact(p_donor_id uuid,p_data jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  update public.donors set
    email=lower(trim(p_data->>'email')),
    phone=trim(p_data->>'phone'),
    street=trim(p_data->>'street'),
    barangay=trim(p_data->>'barangay'),
    municipality=trim(p_data->>'municipality'),
    province=trim(p_data->>'province'),
    updated_at=now()
  where id=p_donor_id;
  if not found then raise exception 'Donor not found'; end if;
end $$;
grant execute on function public.update_donor_contact(uuid,jsonb) to authenticated;

create or replace function public.update_request_status(p_request_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_status not in ('pending','under_review','approved','ready_for_release','rejected','cancelled') then
    raise exception 'Use Release Blood to complete a request';
  end if;
  update public.blood_requests set status=p_status,staff_notes=p_notes,processed_by=auth.uid(),updated_at=now() where id=p_request_id;
  if not found then raise exception 'Request not found'; end if;
end $$;
grant execute on function public.update_request_status(uuid,text,text) to authenticated;

create or replace function public.update_appointment_status(p_appointment_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_status not in ('requested','confirmed','checked_in','completed','cancelled','no_show') then raise exception 'Invalid appointment status'; end if;
  update public.appointments set status=p_status,staff_notes=p_notes,processed_by=auth.uid(),updated_at=now() where id=p_appointment_id;
  if not found then raise exception 'Appointment not found'; end if;
end $$;
grant execute on function public.update_appointment_status(uuid,text,text) to authenticated;

create or replace function public.record_donation_v2(
  p_donor_code text,p_bags integer,p_donation_date date,p_site text,p_appointment_id uuid default null,p_expiry_date date default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_donor public.donors%rowtype; v_donation_id uuid; v_code text; v_balance integer; i integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_bags < 1 or p_bags > 10 then raise exception 'Invalid bag count'; end if;
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

-- Backward-compatible wrapper used by the original client. Blood type is ignored and derived from the donor.
create or replace function public.record_donation(p_donor_code text,p_blood_type text,p_bags integer,p_donation_date date,p_site text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_code text; v_id uuid;
begin
  v_code := public.record_donation_v2(p_donor_code,p_bags,p_donation_date,p_site,null,null);
  select id into v_id from public.donations where donation_code=v_code;
  return v_id;
end $$;
grant execute on function public.record_donation(text,text,integer,date,text) to authenticated;

create or replace function public.release_blood_request(p_request_id uuid,p_notes text default null)
returns text language plpgsql security definer set search_path=public as $$
declare r public.blood_requests%rowtype; v_unit_ids uuid[]; locked_count integer; v_release text; v_balance integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  select * into r from public.blood_requests where id=p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if r.status not in ('approved','ready_for_release') then raise exception 'Request must be approved before blood can be released'; end if;
  select array_agg(id) into v_unit_ids from (
    select id from public.blood_units
    where blood_type=r.blood_type and status='available'
    order by expiry_date nulls last,collection_date nulls last,created_at
    limit r.bags
    for update skip locked
  ) locked_units;
  locked_count := coalesce(array_length(v_unit_ids,1),0);
  if locked_count < r.bags then raise exception 'Insufficient inventory: % bag(s) available for release, % requested',locked_count,r.bags; end if;
  update public.blood_units set status='released',request_id=r.id,updated_at=now() where id=any(v_unit_ids);
  update public.blood_inventory set bags_available=bags_available-r.bags,updated_at=now() where blood_type=r.blood_type returning bags_available into v_balance;
  insert into public.blood_releases(request_id,blood_type,bags,notes,released_by)
  values(r.id,r.blood_type,r.bags,p_notes,auth.uid()) returning release_code into v_release;
  insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,request_id,performed_by)
  values(r.blood_type,-r.bags,v_balance,'release','Blood release '||v_release,r.id,auth.uid());
  update public.blood_requests set status='completed',staff_notes=coalesce(p_notes,staff_notes),processed_by=auth.uid(),updated_at=now() where id=r.id;
  return v_release;
end $$;
grant execute on function public.release_blood_request(uuid,text) to authenticated;

create or replace function public.adjust_inventory(p_blood_type text,p_new_quantity integer,p_reason text)
returns integer language plpgsql security definer set search_path=public as $$
declare v_old integer; v_delta integer; v_type text; i integer;
begin
  if not public.is_staff() then raise exception 'Staff access required'; end if;
  if p_new_quantity < 0 then raise exception 'Quantity cannot be negative'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Adjustment reason is required'; end if;
  select bags_available into v_old from public.blood_inventory where blood_type=p_blood_type for update;
  if v_old is null then raise exception 'Blood type not found'; end if;
  v_delta := p_new_quantity-v_old;
  if v_delta=0 then return v_old; end if;
  if v_delta>0 then
    for i in 1..v_delta loop insert into public.blood_units(blood_type,source,status) values(p_blood_type,'manual / transfer in','available'); end loop;
    v_type := 'transfer_in';
  else
    if (select count(*) from public.blood_units where blood_type=p_blood_type and status='available') < abs(v_delta) then raise exception 'Not enough available units to remove'; end if;
    update public.blood_units set status=case when lower(p_reason) like '%expir%' then 'expired' else 'discarded' end,updated_at=now()
    where id in (select id from public.blood_units where blood_type=p_blood_type and status='available' order by expiry_date nulls last,created_at limit abs(v_delta));
    v_type := case when lower(p_reason) like '%expir%' then 'expired' else 'adjustment' end;
  end if;
  update public.blood_inventory set bags_available=p_new_quantity,updated_at=now() where blood_type=p_blood_type;
  insert into public.inventory_transactions(blood_type,quantity_change,balance_after,transaction_type,reason,performed_by)
  values(p_blood_type,v_delta,p_new_quantity,v_type,p_reason,auth.uid());
  return p_new_quantity;
end $$;
grant execute on function public.adjust_inventory(text,integer,text) to authenticated;

-- Admin can connect an already-created Supabase Authentication user to the portal by email.
create or replace function public.admin_link_staff_by_email(p_email text,p_full_name text,p_role text default 'staff')
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_role not in ('staff','admin') then raise exception 'Invalid role'; end if;
  select id into v_id from auth.users where lower(email)=lower(trim(p_email));
  if v_id is null then raise exception 'Create this email in Authentication > Users first'; end if;
  insert into public.staff_profiles(id,email,full_name,role,active)
  values(v_id,lower(trim(p_email)),trim(p_full_name),p_role,true)
  on conflict(id) do update set email=excluded.email,full_name=excluded.full_name,role=excluded.role,active=true;
  return v_id;
end $$;
grant execute on function public.admin_link_staff_by_email(text,text,text) to authenticated;

create or replace function public.admin_update_staff(p_id uuid,p_role text,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_role not in ('staff','admin') then raise exception 'Invalid role'; end if;
  if p_id=auth.uid() and p_active=false then raise exception 'You cannot disable your own account'; end if;
  if p_id=auth.uid() and p_role<>'admin' then raise exception 'You cannot remove your own administrator role'; end if;
  update public.staff_profiles set role=p_role,active=p_active where id=p_id;
end $$;
grant execute on function public.admin_update_staff(uuid,text,boolean) to authenticated;

-- ============================================================
-- RLS
-- ============================================================
alter table public.staff_profiles enable row level security;
alter table public.donors enable row level security;
alter table public.blood_inventory enable row level security;
alter table public.blood_requests enable row level security;
alter table public.appointments enable row level security;
alter table public.donations enable row level security;
alter table public.blood_units enable row level security;
alter table public.blood_releases enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.announcements enable row level security;
alter table public.events enable row level security;
alter table public.facilities enable row level security;
alter table public.audit_logs enable row level security;

-- Drop old policies that could be broader than BloodCare 2.0.
do $$
declare p record;
begin
  for p in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename in
    ('staff_profiles','donors','blood_inventory','blood_requests','appointments','donations','blood_units','blood_releases','inventory_transactions','announcements','events','facilities','audit_logs') loop
    execute format('drop policy if exists %I on %I.%I',p.policyname,p.schemaname,p.tablename);
  end loop;
end $$;

create policy "profiles self or admin read" on public.staff_profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy "admin profiles update" on public.staff_profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());

create policy "staff donors read" on public.donors for select to authenticated using(public.is_staff());
create policy "admin donors delete" on public.donors for delete to authenticated using(public.is_admin());

create policy "public inventory read" on public.blood_inventory for select to anon,authenticated using(true);
create policy "staff requests read" on public.blood_requests for select to authenticated using(public.is_staff());
create policy "admin requests delete" on public.blood_requests for delete to authenticated using(public.is_admin());
create policy "staff appointments read" on public.appointments for select to authenticated using(public.is_staff());
create policy "admin appointments delete" on public.appointments for delete to authenticated using(public.is_admin());
create policy "staff donations read" on public.donations for select to authenticated using(public.is_staff());
create policy "staff units read" on public.blood_units for select to authenticated using(public.is_staff());
create policy "staff releases read" on public.blood_releases for select to authenticated using(public.is_staff());
create policy "staff inventory movements read" on public.inventory_transactions for select to authenticated using(public.is_staff());

create policy "public announcements read" on public.announcements for select to anon,authenticated using(published=true or public.is_staff());
create policy "staff announcements insert" on public.announcements for insert to authenticated with check(public.is_staff());
create policy "staff announcements update" on public.announcements for update to authenticated using(public.is_staff()) with check(public.is_staff());
create policy "staff announcements delete" on public.announcements for delete to authenticated using(public.is_staff());
create policy "public events read" on public.events for select to anon,authenticated using(published=true or public.is_staff());
create policy "staff events insert" on public.events for insert to authenticated with check(public.is_staff());
create policy "staff events update" on public.events for update to authenticated using(public.is_staff()) with check(public.is_staff());
create policy "staff events delete" on public.events for delete to authenticated using(public.is_staff());

create policy "public facilities read" on public.facilities for select to anon,authenticated using(active=true or public.is_staff());
create policy "admin facilities insert" on public.facilities for insert to authenticated with check(public.is_admin());
create policy "admin facilities update" on public.facilities for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin facilities delete" on public.facilities for delete to authenticated using(public.is_admin());
create policy "admin audit read" on public.audit_logs for select to authenticated using(public.is_admin());

-- ============================================================
-- Event image storage
-- ============================================================
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('event-images','event-images',true,5242880,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update set public=true,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "public event image read" on storage.objects;
drop policy if exists "staff event image upload" on storage.objects;
drop policy if exists "staff event image update" on storage.objects;
drop policy if exists "staff event image delete" on storage.objects;
create policy "public event image read" on storage.objects for select to public using(bucket_id='event-images');
create policy "staff event image upload" on storage.objects for insert to authenticated with check(bucket_id='event-images' and public.is_staff());
create policy "staff event image update" on storage.objects for update to authenticated using(bucket_id='event-images' and public.is_staff()) with check(bucket_id='event-images' and public.is_staff());
create policy "staff event image delete" on storage.objects for delete to authenticated using(bucket_id='event-images' and public.is_staff());

-- ============================================================
-- Demo content
-- ============================================================
insert into public.announcements(title,body,published)
select 'National Blood Donation Drive','Join the National Blood Donation activity on October 12, 2026. Please check the Events section for the venue and schedule.',true
where not exists(select 1 from public.announcements);
insert into public.events(title,description,event_date,location,published)
select 'Community Blood Donation Day','Bring a valid ID and follow the on-site screening process.','2026-10-12','Evacuation Center',true
where not exists(select 1 from public.events);
insert into public.facilities(name,facility_type,address,municipality,province,operating_hours,services,latitude,longitude,active)
select 'BloodCare Community Donation Center','Donation Center','Evacuation Center','Buenavista','Bohol','8:00 AM - 5:00 PM','Donor screening, blood donation and appointment assistance',10.0440,124.1680,true
where not exists(select 1 from public.facilities);

-- First admin bootstrap example. Create the user in Authentication > Users first, then run:
-- insert into public.staff_profiles(id,email,full_name,role,active)
-- select id,email,'System Administrator','admin',true from auth.users where email='admin@bloodcare.com'
-- on conflict(id) do update set role='admin',active=true;
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

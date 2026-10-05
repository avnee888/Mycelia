-- DANGER: DROPS ALL DATA
drop table if exists interactions cascade;
drop table if exists edges cascade;
drop table if exists contact_clusters cascade;
drop table if exists contacts cascade;
drop table if exists clusters cascade;

-- Clerk reads JWT 'sub' claim from claims JSON
create or replace function requesting_user_id()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::text;
$$;

create table clusters (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  name varchar(100) not null check (char_length(trim(name)) > 0),
  color varchar(7) default '#6366f1' check (color ~* '^#[0-9a-f]{6}$'),
  ui_x numeric default 0,
  ui_y numeric default 0,
  created_at timestamptz default now()
);

create table contacts (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  name varchar(100) not null check (char_length(trim(name)) > 0),
  email varchar(255),
  phone varchar(50),
  notes varchar(2000),
  avatar_url text,
  custom_dates jsonb default '{}'::jsonb,
  cadence_days integer check (cadence_days > 0),
  last_contacted_at timestamptz,
  ui_x numeric default 0,
  ui_y numeric default 0,
  created_at timestamptz default now()
);

create table contact_clusters (
  contact_id uuid not null references contacts(id) on delete cascade,
  cluster_id uuid not null references clusters(id) on delete cascade,
  source_handle varchar(50),
  target_handle varchar(50),
  label varchar(100),
  primary key (contact_id, cluster_id)
);

create table edges (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  source_id uuid not null references contacts(id) on delete cascade,
  target_id uuid not null references contacts(id) on delete cascade,
  source_handle varchar(50),
  target_handle varchar(50),
  label varchar(100) not null check (char_length(trim(label)) > 0),
  created_at timestamptz default now()
);

create table interactions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  contact_id uuid not null references contacts(id) on delete cascade,
  note varchar(2000) not null check (char_length(trim(note)) > 0),
  occurred_at timestamptz default now(),
  created_at timestamptz default now()
);

-- RLS
alter table clusters enable row level security;
alter table contacts enable row level security;
alter table contact_clusters enable row level security;
alter table edges enable row level security;
alter table interactions enable row level security;

create policy "Users see own clusters" on clusters for all using (requesting_user_id() = user_id) with check (requesting_user_id() = user_id);
create policy "Users see own contacts" on contacts for all using (requesting_user_id() = user_id) with check (requesting_user_id() = user_id);
create policy "Users see own contact_clusters" on contact_clusters for all using (
  contact_id in (select id from contacts where user_id = requesting_user_id())
) with check (
  contact_id in (select id from contacts where user_id = requesting_user_id())
);
create policy "Users see own edges" on edges for all using (requesting_user_id() = user_id) with check (requesting_user_id() = user_id);
create policy "Users see own interactions" on interactions for all using (requesting_user_id() = user_id) with check (requesting_user_id() = user_id);

CREATE OR REPLACE FUNCTION update_last_contacted_at()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE contacts SET last_contacted_at = NEW.occurred_at
  WHERE id = NEW.contact_id AND (last_contacted_at IS NULL OR last_contacted_at < NEW.occurred_at);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_last_contacted_at ON interactions;
CREATE TRIGGER trigger_update_last_contacted_at
AFTER INSERT ON interactions
FOR EACH ROW EXECUTE FUNCTION update_last_contacted_at();

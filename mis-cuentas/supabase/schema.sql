-- ===== MIS CUENTAS · esquema Supabase =====
-- Pégalo entero en Supabase → SQL Editor → Run.

create table public.cuentas (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (length(trim(nombre)) > 0),
  tipo text not null default 'Cuenta corriente',
  saldo_inicial numeric(14,2) not null default 0,
  color text not null default '#2f6fd6',
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.cuenta_miembros (
  cuenta_id uuid not null references public.cuentas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rol text not null default 'editor' check (rol in ('propietario','editor','lector')),
  created_at timestamptz not null default now(),
  primary key (cuenta_id, user_id)
);
create index on public.cuenta_miembros (user_id);

create table public.apartados (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references public.cuentas(id) on delete cascade,
  nombre text not null,
  color text not null default '#8a8f9c',
  tipo text not null default 'gasto' check (tipo in ('gasto','ingreso','ambos'))
);
create index on public.apartados (cuenta_id);

create table public.movimientos (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references public.cuentas(id) on delete cascade,
  apartado_id uuid references public.apartados(id) on delete set null,
  tipo text not null check (tipo in ('gasto','ingreso')),
  concepto text not null default '',
  importe numeric(14,2) not null check (importe > 0),
  fecha date not null default current_date,
  creado_por uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index on public.movimientos (cuenta_id, fecha desc);

-- Invitaciones (correo interno)
create table public.invitaciones (
  id uuid primary key default gen_random_uuid(),
  cuenta_id uuid not null references public.cuentas(id) on delete cascade,
  cuenta_nombre text not null,
  de_user uuid not null references auth.users(id) on delete cascade,
  de_email text not null,
  para_user uuid not null references auth.users(id) on delete cascade,
  para_email text not null,
  rol text not null check (rol in ('editor','lector')),
  estado text not null default 'pendiente' check (estado in ('pendiente','aceptada','denegada')),
  created_at timestamptz not null default now(),
  respondida_at timestamptz
);
create index on public.invitaciones (para_user, estado);
create index on public.invitaciones (de_user);
create unique index invitacion_pendiente_unica on public.invitaciones (cuenta_id, para_user) where estado = 'pendiente';

-- ---------- funciones auxiliares ----------
create or replace function public.es_miembro(p_cuenta uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from cuenta_miembros where cuenta_id = p_cuenta and user_id = auth.uid());
$$;

create or replace function public.es_propietario(p_cuenta uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from cuenta_miembros where cuenta_id = p_cuenta and user_id = auth.uid() and rol = 'propietario');
$$;

-- Al crear una cuenta: el creador pasa a ser propietario y se crean apartados por defecto
create or replace function public.cuenta_nueva() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into cuenta_miembros (cuenta_id, user_id, rol) values (new.id, new.owner_id, 'propietario');
  insert into apartados (cuenta_id, nombre, color, tipo) values
    (new.id, 'Federación Andaluza', '#2e9e5b', 'ambos'),
    (new.id, 'Gimnasio',            '#2f6fd6', 'ambos'),
    (new.id, 'Casa',                '#e08a1e', 'gasto'),
    (new.id, 'Comida',              '#c2412d', 'gasto'),
    (new.id, 'Nómina',              '#8a4fd1', 'ingreso');
  return new;
end $$;

create trigger cuenta_nueva after insert on public.cuentas
for each row execute function public.cuenta_nueva();

-- ¿Puede modificar? (propietario o editor; el "lector" solo ve)
create or replace function public.puede_editar(p_cuenta uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from cuenta_miembros where cuenta_id = p_cuenta and user_id = auth.uid() and rol in ('propietario','editor'));
$$;

-- Invitar a una persona ya registrada (solo el propietario). p_rol: 'editor' (participante) o 'lector' (solo ver)
create or replace function public.invitar_cuenta(p_cuenta uuid, p_email text, p_rol text) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_email text; v_nombre text; v_mi text;
begin
  if not es_propietario(p_cuenta) then
    raise exception 'Solo el propietario puede invitar a otras personas.';
  end if;
  if p_rol not in ('editor','lector') then
    raise exception 'Tipo de invitación no válido.';
  end if;
  select id, email::text into v_user, v_email from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then
    raise exception 'No existe ningún usuario con ese correo. Créalo antes en Supabase.';
  end if;
  if v_user = auth.uid() then
    raise exception 'No puedes invitarte a ti mismo.';
  end if;
  if exists (select 1 from cuenta_miembros where cuenta_id = p_cuenta and user_id = v_user) then
    raise exception 'Esa persona ya tiene acceso a esta cuenta.';
  end if;
  if exists (select 1 from invitaciones where cuenta_id = p_cuenta and para_user = v_user and estado = 'pendiente') then
    raise exception 'Ya hay una invitación pendiente para esa persona.';
  end if;
  select nombre into v_nombre from cuentas where id = p_cuenta;
  select email::text into v_mi from auth.users where id = auth.uid();
  insert into invitaciones (cuenta_id, cuenta_nombre, de_user, de_email, para_user, para_email, rol)
  values (p_cuenta, v_nombre, auth.uid(), v_mi, v_user, v_email, p_rol);
end $$;

-- Aceptar o denegar una invitación recibida
create or replace function public.responder_invitacion(p_id uuid, p_aceptar boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v invitaciones%rowtype;
begin
  select * into v from invitaciones where id = p_id and para_user = auth.uid() and estado = 'pendiente' for update;
  if not found then
    raise exception 'La invitación ya no está disponible.';
  end if;
  if p_aceptar then
    insert into cuenta_miembros (cuenta_id, user_id, rol) values (v.cuenta_id, auth.uid(), v.rol)
    on conflict do nothing;
  end if;
  update invitaciones set estado = case when p_aceptar then 'aceptada' else 'denegada' end, respondida_at = now() where id = p_id;
end $$;

-- Miembros (con correo) de todas las cuentas a las que tienes acceso
create or replace function public.miembros_mis_cuentas()
returns table (cuenta_id uuid, user_id uuid, email text, rol text)
language sql security definer stable set search_path = public as $$
  select m.cuenta_id, m.user_id, u.email::text, m.rol
  from cuenta_miembros m join auth.users u on u.id = m.user_id
  where m.cuenta_id in (select cuenta_id from cuenta_miembros where user_id = auth.uid())
  order by m.rol desc, u.email;
$$;

-- Lista de miembros (con correo) de una cuenta de la que eres miembro
create or replace function public.miembros_cuenta(p_cuenta uuid)
returns table (user_id uuid, email text, rol text)
language sql security definer stable set search_path = public as $$
  select m.user_id, u.email::text, m.rol
  from cuenta_miembros m join auth.users u on u.id = m.user_id
  where m.cuenta_id = p_cuenta and es_miembro(p_cuenta)
  order by m.rol desc, u.email;
$$;

-- Vista con saldo, nº de miembros y tu rol (respeta la seguridad de cada usuario)
create view public.cuentas_resumen with (security_invoker = true) as
select c.id, c.nombre, c.tipo, c.color, c.saldo_inicial, c.owner_id, c.created_at,
  c.saldo_inicial + coalesce(sum(case when m.tipo = 'ingreso' then m.importe else -m.importe end), 0) as saldo,
  (select count(*) from cuenta_miembros cm where cm.cuenta_id = c.id) as num_miembros,
  (select cm.rol from cuenta_miembros cm where cm.cuenta_id = c.id and cm.user_id = auth.uid()) as mi_rol
from cuentas c left join movimientos m on m.cuenta_id = c.id
group by c.id;

-- ---------- seguridad (RLS) ----------
alter table public.cuentas         enable row level security;
alter table public.cuenta_miembros enable row level security;
alter table public.apartados       enable row level security;
alter table public.movimientos     enable row level security;

create policy "ver cuentas"    on public.cuentas for select to authenticated using (es_miembro(id) or owner_id = auth.uid());
create policy "crear cuentas"  on public.cuentas for insert to authenticated with check (owner_id = auth.uid());

create policy "borrar cuentas" on public.cuentas for delete to authenticated using (es_propietario(id));

create policy "ver miembros"    on public.cuenta_miembros for select to authenticated using (es_miembro(cuenta_id));
create policy "quitar miembros" on public.cuenta_miembros for delete to authenticated
  using (rol <> 'propietario' and (es_propietario(cuenta_id) or user_id = auth.uid()));

alter table public.invitaciones enable row level security;
create policy "ver invitaciones"      on public.invitaciones for select to authenticated using (para_user = auth.uid() or de_user = auth.uid());
create policy "cancelar invitaciones" on public.invitaciones for delete to authenticated using (de_user = auth.uid() and estado = 'pendiente');

create policy "editar cuentas" on public.cuentas for update to authenticated using (puede_editar(id)) with check (puede_editar(id));

create policy "ver apartados"      on public.apartados for select to authenticated using (es_miembro(cuenta_id));
create policy "crear apartados"    on public.apartados for insert to authenticated with check (puede_editar(cuenta_id));
create policy "editar apartados"   on public.apartados for update to authenticated using (puede_editar(cuenta_id)) with check (puede_editar(cuenta_id));
create policy "borrar apartados"   on public.apartados for delete to authenticated using (puede_editar(cuenta_id));

create policy "ver movimientos"    on public.movimientos for select to authenticated using (es_miembro(cuenta_id));
create policy "crear movimientos"  on public.movimientos for insert to authenticated with check (puede_editar(cuenta_id));
create policy "editar movimientos" on public.movimientos for update to authenticated using (puede_editar(cuenta_id)) with check (puede_editar(cuenta_id));
create policy "borrar movimientos" on public.movimientos for delete to authenticated using (puede_editar(cuenta_id));

-- ---------- permisos ----------
revoke all on all tables in schema public from anon;
grant usage on schema public to authenticated;
grant select, insert, delete on public.cuentas to authenticated;
grant update (nombre, tipo, saldo_inicial, color) on public.cuentas to authenticated;  -- nadie puede cambiar el propietario
grant select, delete on public.cuenta_miembros to authenticated;                       -- las altas solo van por responder_invitacion()
grant select, insert, update, delete on public.apartados, public.movimientos to authenticated;
grant select on public.cuentas_resumen to authenticated;

revoke execute on function public.miembros_cuenta(uuid), public.es_miembro(uuid), public.es_propietario(uuid) from public, anon;
grant  execute on function public.miembros_cuenta(uuid), public.es_miembro(uuid), public.es_propietario(uuid) to authenticated;

revoke all on public.invitaciones from anon, authenticated;
grant select, delete on public.invitaciones to authenticated;

revoke execute on function public.puede_editar(uuid), public.invitar_cuenta(uuid, text, text), public.responder_invitacion(uuid, boolean), public.miembros_mis_cuentas() from public, anon;
grant  execute on function public.puede_editar(uuid), public.invitar_cuenta(uuid, text, text), public.responder_invitacion(uuid, boolean), public.miembros_mis_cuentas() to authenticated;

-- ---------- tiempo real (los cambios de tu pareja aparecen al instante) ----------
alter publication supabase_realtime add table public.cuentas, public.cuenta_miembros, public.apartados, public.movimientos, public.invitaciones;

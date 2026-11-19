-- MIS CUENTAS · acceso compartido a movimientos, apartados y repartos
-- Ejecutar en Supabase > SQL Editor como administrador.
-- Todos los miembros (propietario, editor y lector) pueden VER los movimientos
-- y apartados de las cuentas de las que son miembros. Solo propietario/editor
-- pueden crear, editar o borrar movimientos.

begin;

alter table public.movimientos enable row level security;
alter table public.apartados enable row level security;

-- Lectura compartida de movimientos: acceso por pertenencia a la cuenta,
-- nunca por creado_por. Así cada miembro ve también lo registrado por los demás.
drop policy if exists "ver movimientos" on public.movimientos;
create policy "ver movimientos"
on public.movimientos
for select
to authenticated
using (
  exists (
    select 1
    from public.cuenta_miembros cm
    where cm.cuenta_id = movimientos.cuenta_id
      and cm.user_id = (select auth.uid())
  )
);

-- Los apartados también deben ser visibles para que todos vean los nombres,
-- colores y porcentajes correctos en los repartos.
drop policy if exists "ver apartados" on public.apartados;
create policy "ver apartados"
on public.apartados
for select
to authenticated
using (
  exists (
    select 1
    from public.cuenta_miembros cm
    where cm.cuenta_id = apartados.cuenta_id
      and cm.user_id = (select auth.uid())
  )
);

-- Solo propietarios y editores pueden modificar movimientos.
drop policy if exists "crear movimientos" on public.movimientos;
create policy "crear movimientos"
on public.movimientos
for insert
to authenticated
with check (
  exists (
    select 1 from public.cuenta_miembros cm
    where cm.cuenta_id = movimientos.cuenta_id
      and cm.user_id = (select auth.uid())
      and cm.rol in ('propietario', 'editor')
  )
);

drop policy if exists "editar movimientos" on public.movimientos;
create policy "editar movimientos"
on public.movimientos
for update
to authenticated
using (
  exists (
    select 1 from public.cuenta_miembros cm
    where cm.cuenta_id = movimientos.cuenta_id
      and cm.user_id = (select auth.uid())
      and cm.rol in ('propietario', 'editor')
  )
)
with check (
  exists (
    select 1 from public.cuenta_miembros cm
    where cm.cuenta_id = movimientos.cuenta_id
      and cm.user_id = (select auth.uid())
      and cm.rol in ('propietario', 'editor')
  )
);

drop policy if exists "borrar movimientos" on public.movimientos;
create policy "borrar movimientos"
on public.movimientos
for delete
to authenticated
using (
  exists (
    select 1 from public.cuenta_miembros cm
    where cm.cuenta_id = movimientos.cuenta_id
      and cm.user_id = (select auth.uid())
      and cm.rol in ('propietario', 'editor')
  )
);

-- Permisos SQL necesarios; RLS sigue controlando qué filas puede ver cada usuario.
grant select, insert, update, delete on public.movimientos to authenticated;
grant select, insert, update, delete on public.apartados to authenticated;

-- Activar Realtime de forma idempotente para que los cambios de un miembro
-- se reflejen en la pantalla de los demás miembros conectados.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'movimientos'
  ) then
    alter publication supabase_realtime add table public.movimientos;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'apartados'
  ) then
    alter publication supabase_realtime add table public.apartados;
  end if;
end
$$;

commit;

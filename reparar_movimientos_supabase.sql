-- MIS CUENTAS · reparación de permisos para borrar movimientos
-- Ejecutar en Supabase > SQL Editor con el usuario administrador.
-- Permite borrar movimientos únicamente a propietarios y editores de esa cuenta.

begin;

alter table public.movimientos enable row level security;

-- Elimina posibles versiones anteriores de la política con este nombre.
drop policy if exists "borrar movimientos" on public.movimientos;

create policy "borrar movimientos"
on public.movimientos
for delete
to authenticated
using (
  exists (
    select 1
    from public.cuenta_miembros cm
    where cm.cuenta_id = movimientos.cuenta_id
      and cm.user_id = (select auth.uid())
      and cm.rol in ('propietario', 'editor')
  )
);

-- DELETE permite ejecutar el borrado; SELECT permite al HTML confirmar
-- mediante .delete().select('id') que realmente se eliminó una fila.
grant usage on schema public to authenticated;
grant select, delete on table public.movimientos to authenticated;

commit;

-- Comprobación de la política instalada:
select
  policyname,
  cmd,
  roles,
  qual
from pg_policies
where schemaname = 'public'
  and tablename = 'movimientos'
  and cmd = 'DELETE';

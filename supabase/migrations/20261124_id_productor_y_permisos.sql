-- SCRUM-3 · Permisos de las columnas nuevas, ID de productor y UPP compartida
-- El ID de productor es distinto de la UPP: la UPP es de la granja y la pueden
-- usar varios productores. La clave queda así:
--   Al dar de alta la miel:  UPP-IDproductor-Ssemana-año
--   Producto terminado:      UPP-IDproductor-Ssemana-año-gramaje
-- Requiere 20261123_clave_trazabilidad.sql. Se puede correr más de una vez.
-- No cambia las claves ya generadas.

begin;

-- 1. ID de productor. Los productores existentes quedan vacíos: se captura
--    desde la app y es obligatorio para dar de alta su miel.
alter table public.proveedores
  add column if not exists id_productor text
    check (id_productor ~ '^[A-Z0-9]+$');
create unique index if not exists proveedores_id_productor_key
  on public.proveedores (id_productor);

-- 2. La UPP deja de ser única (RASMIEL no se toca)
do $$
declare
  r record;
begin
  for r in
    select x.indexrelid::regclass as indice, c.conname
    from pg_index x
    join pg_attribute a on a.attrelid = x.indrelid and a.attname = 'upp_id'
    left join pg_constraint c
      on c.conindid = x.indexrelid and c.conrelid = x.indrelid
     and c.contype = 'u'
    where x.indrelid = 'public.proveedores'::regclass
      and x.indisunique and not x.indisprimary
      and x.indnkeyatts = 1 and x.indkey[0] = a.attnum
  loop
    if r.conname is not null then
      execute format('alter table public.proveedores drop constraint %I',
                     r.conname);
    else
      execute 'drop index ' || r.indice;
    end if;
  end loop;
end;
$$;

create index if not exists proveedores_upp_id_idx
  on public.proveedores (upp_id);

-- 3. Permisos sobre las columnas nuevas (las filas las sigue limitando RLS)
grant select (es_miel), insert (es_miel), update (es_miel)
  on public.insumos to authenticated;
grant select (gramaje, gramaje_unidad), insert (gramaje, gramaje_unidad),
      update (gramaje, gramaje_unidad)
  on public.productos to authenticated;
grant select (id_productor, upp_otro, upp_otro_nombre),
      insert (id_productor, upp_otro, upp_otro_nombre),
      update (id_productor, upp_otro, upp_otro_nombre)
  on public.proveedores to authenticated;
grant select (proveedor_id, clave, upp_origen, entrada_id),
      insert (proveedor_id, upp_origen, entrada_id)
  on public.movimientos to authenticated;
grant select (clave, entrada_id) on public.lotes to authenticated;

-- 4. La clave incluye el ID de productor
create or replace function public.asignar_clave_movimiento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_prov proveedores%rowtype;
  v_ent  movimientos%rowtype;
begin
  new.clave := null;

  if new.cantidad > 0 then
    new.entrada_id := null;
    if new.proveedor_id is not null and exists (
         select 1 from insumos where id = new.insumo_id and es_miel) then
      select * into v_prov from proveedores where id = new.proveedor_id;
      if v_prov.id_productor is null then
        raise exception 'Captura el ID de % en Proveedores para generar su clave',
          v_prov.nombre;
      end if;
      new.upp_origen := coalesce(new.upp_origen, v_prov.upp_id);
      if new.upp_origen <> v_prov.upp_id
         and new.upp_origen is distinct from v_prov.upp_otro then
        raise exception 'La UPP de origen no corresponde al productor';
      end if;
      new.clave := clave_origen(new.upp_origen || '-' || v_prov.id_productor,
                                coalesce(new.created_at, now()));
    else
      new.upp_origen := null;
    end if;

  elsif new.entrada_id is not null then
    -- El bloqueo evita que dos salidas simultáneas usen la misma miel
    select * into v_ent from movimientos
      where id = new.entrada_id for update;
    if v_ent.id is null or v_ent.clave is null
       or v_ent.insumo_id is distinct from new.insumo_id then
      raise exception 'La entrada de miel seleccionada no es válida';
    end if;
    if entrada_disponible(v_ent.id) + new.cantidad < 0 then
      raise exception 'La entrada % solo tiene % disponible',
        v_ent.clave, entrada_disponible(v_ent.id);
    end if;
    new.clave := v_ent.clave;
    new.upp_origen := v_ent.upp_origen;
    new.proveedor_id := v_ent.proveedor_id;
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';
commit;

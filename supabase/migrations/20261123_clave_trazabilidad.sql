-- SCRUM-3 · Clave de trazabilidad ("priva") de origen a producto terminado
--   Al dar de alta la miel:  UPP-Ssemana-año            310960142001-S47-2026
--   Producto terminado:      UPP-Ssemana-año-gramaje    310960142001-S47-2026-500G
-- La semana es la de ENTRADA de la miel (ISO, hora de Mérida).
-- Requiere 20261122_movimientos_proveedor.sql. Se puede correr más de una vez.
-- No modifica registrar_salida_producto: la envuelve.

begin;

-- 1. Columnas
alter table public.insumos
  add column if not exists es_miel boolean not null default false;

alter table public.productos
  add column if not exists gramaje numeric check (gramaje > 0),
  add column if not exists gramaje_unidad text not null default 'g'
    check (gramaje_unidad in ('g', 'kg'));

-- UPP de otro: granja externa (abejas ajenas). Sin UNIQUE: se puede compartir.
alter table public.proveedores
  add column if not exists upp_otro text check (upp_otro ~ '^[0-9]{12}$'),
  add column if not exists upp_otro_nombre text;

alter table public.movimientos
  add column if not exists clave text,
  add column if not exists upp_origen text,
  add column if not exists entrada_id uuid references public.movimientos (id);

alter table public.lotes
  add column if not exists clave text,
  add column if not exists entrada_id uuid references public.movimientos (id);

create index if not exists movimientos_entrada_id_idx
  on public.movimientos (entrada_id);
create index if not exists lotes_entrada_id_idx on public.lotes (entrada_id);

-- 2. Clave de origen
create or replace function public.clave_origen(p_upp text, p_fecha timestamptz)
returns text language sql stable set search_path = public as $$
  select p_upp || '-S'
    || to_char(p_fecha at time zone 'America/Merida', 'IW-IYYY');
$$;

-- 3. Cuánto queda de una entrada (descuenta salidas manuales y producto)
create or replace function public.entrada_disponible(p_entrada uuid)
returns numeric language sql stable set search_path = public as $$
  select (e.cantidad
    + coalesce((select sum(m.cantidad) from movimientos m
                where m.entrada_id = e.id), 0)
    + coalesce((select sum(m.cantidad) from movimientos m
                join lotes l on l.id = m.lote_id
                where l.entrada_id = e.id
                  and m.insumo_id = e.insumo_id
                  and m.cantidad < 0), 0))::numeric
  from movimientos e where e.id = p_entrada;
$$;

-- 4. Al guardar un movimiento: generar la clave o heredarla
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
      new.upp_origen := coalesce(new.upp_origen, v_prov.upp_id);
      if new.upp_origen <> v_prov.upp_id
         and new.upp_origen is distinct from v_prov.upp_otro then
        raise exception 'La UPP de origen no corresponde al productor';
      end if;
      new.clave := clave_origen(new.upp_origen,
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

drop trigger if exists asignar_clave_movimiento on public.movimientos;
create trigger asignar_clave_movimiento
  before insert on public.movimientos
  for each row execute function public.asignar_clave_movimiento();

-- 5. Salida de producto: llama a la función existente y enlaza el origen.
--    Todo ocurre en una transacción: si algo falla no se descuenta nada.
create or replace function public.registrar_salida_trazable(
  p_producto uuid, p_cantidad numeric, p_nota text, p_flora text,
  p_apiario text, p_entrada uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prod  productos%rowtype;
  v_ent   movimientos%rowtype;
  v_lote  jsonb;
  v_id    uuid;
  v_clave text;
  v_mieles int;
begin
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor que cero';
  end if;
  select * into v_prod from productos where id = p_producto;
  if v_prod.id is null then
    raise exception 'El producto no existe';
  end if;

  select count(*) into v_mieles
    from producto_insumos r join insumos i on i.id = r.insumo_id
    where r.producto_id = p_producto and i.es_miel;

  if v_mieles > 1 then
    raise exception 'La receta usa más de un tipo de miel: falta definir qué clave hereda';
  end if;
  if v_mieles = 0 and p_entrada is not null then
    raise exception 'La receta de este producto no usa miel';
  end if;
  if v_mieles = 1 then
    if p_entrada is null then
      raise exception 'Selecciona la entrada de miel de origen';
    end if;
    if v_prod.gramaje is null then
      raise exception 'Define el gramaje del producto para generar su clave';
    end if;
    select * into v_ent from movimientos where id = p_entrada for update;
    if v_ent.id is null or v_ent.clave is null or not exists (
         select 1 from producto_insumos
         where producto_id = p_producto and insumo_id = v_ent.insumo_id) then
      raise exception 'La entrada de miel no corresponde a la receta';
    end if;
    v_clave := v_ent.clave || '-' || trim_scale(v_prod.gramaje)
      || upper(v_prod.gramaje_unidad);
  end if;

  select to_jsonb(r) into v_lote
    from registrar_salida_producto(
      p_producto => p_producto, p_cantidad => p_cantidad, p_nota => p_nota,
      p_flora => p_flora, p_apiario => p_apiario) r;

  if v_mieles = 0 then
    return v_lote;
  end if;

  select id into v_id from lotes
    where id = (v_lote ->> 'id')::uuid
       or (v_lote ->> 'id' is null and codigo = v_lote ->> 'codigo')
    order by created_at desc limit 1;
  if v_id is null then
    raise exception 'No se encontró el registro de salida para asignar su clave';
  end if;
  update lotes set clave = v_clave, entrada_id = p_entrada where id = v_id;

  if entrada_disponible(p_entrada) < 0 then
    raise exception 'La entrada % no tiene miel suficiente para esta salida',
      v_ent.clave;
  end if;

  return v_lote || jsonb_build_object('clave', v_clave);
end;
$$;

revoke all on function public.registrar_salida_trazable(
  uuid, numeric, text, text, text, uuid) from public, anon;
grant execute on function public.registrar_salida_trazable(
  uuid, numeric, text, text, text, uuid) to authenticated;

-- 6. Entradas de miel con su saldo (para los selectores de la app)
create or replace view public.entradas_miel with (security_invoker = true) as
select m.id, m.clave, m.created_at, m.insumo_id, m.upp_origen,
       i.nombre as insumo, i.unidad, p.nombre as productor,
       public.entrada_disponible(m.id) as disponible
from public.movimientos m
join public.insumos i on i.id = m.insumo_id
left join public.proveedores p on p.id = m.proveedor_id
where m.cantidad > 0 and m.clave is not null;

revoke all on public.entradas_miel from anon;
grant select on public.entradas_miel to authenticated;

-- 7. Datos existentes. Se pausan los triggers propios de movimientos para
--    que rellenar la clave no vuelva a mover la existencia.
update public.insumos set es_miel = true
  where nombre ilike 'miel%' and not es_miel;

alter table public.movimientos disable trigger user;
update public.movimientos m
  set upp_origen = p.upp_id,
      clave = public.clave_origen(p.upp_id, m.created_at)
  from public.proveedores p, public.insumos i
  where p.id = m.proveedor_id and i.id = m.insumo_id
    and i.es_miel and m.cantidad > 0 and m.clave is null;
alter table public.movimientos enable trigger user;

notify pgrst, 'reload schema';
commit;

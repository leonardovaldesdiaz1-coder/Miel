-- SCRUM-3 · Trazabilidad de entradas y salidas
-- Liga cada movimiento de insumo con el proveedor (UPP / RASMIEL) de origen.
-- Ejecutar en Supabase > SQL Editor antes de usar la pestaña de Trazabilidad.

alter table public.movimientos
  add column if not exists proveedor_id uuid
    references public.proveedores (id) on delete set null;

create index if not exists movimientos_proveedor_id_idx
  on public.movimientos (proveedor_id);

-- Refresca el caché de esquema de PostgREST para que la relación
-- movimientos -> proveedores esté disponible de inmediato.
notify pgrst, 'reload schema';

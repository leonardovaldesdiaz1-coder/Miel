// Proyecto app_miel · lib/main.dart
// Antes: flutter pub add supabase_flutter
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Alias para no escribir List<Map<String, dynamic>> en todos lados
/// (y evitar que se pierdan los < > al copiar y pegar).
typedef Filas = List<Map<String, dynamic>>;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://sncgfqvcmskstayoviwi.supabase.co',
    publishableKey: 'sb_publishable_1Rm5rRK3HXDD5zYOblBVtg_DlyzTwDj',
  );
  runApp(const ApiculturaApp());
}

final db = Supabase.instance.client;
const ambar = Color(0xFFD97706);
const cafe = Color(0xFF78350F);
final grande = FilledButton.styleFrom(
    backgroundColor: ambar,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 56),
    textStyle: const TextStyle(fontSize: 18));
final grandeSuave = FilledButton.styleFrom(
    minimumSize: const Size(0, 56), textStyle: const TextStyle(fontSize: 18));

void aviso(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

String fmt(Object? n) {
  final v = n is num ? n : (num.tryParse('${n ?? 0}') ?? 0);
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

String msgError(Object e) {
  if (e is PostgrestException) {
    if (e.code == '23514') return 'Existencia insuficiente o formato inválido';
    if (e.code == '23503') {
      return 'No se puede eliminar: tiene movimientos, lotes o recetas asociados';
    }
    if (e.code == '23505') {
      return 'Ya existe un registro con esa Clave UPP o Clave RASMIEL';
    }
    return e.message;
  }
  return 'Error: $e';
}

Stream<Filas> flujo(String t) =>
    db.from(t).stream(primaryKey: ['id']).order('nombre');

Widget titulo(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(t,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: cafe)),
    );

class ApiculturaApp extends StatelessWidget {
  const ApiculturaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Gestión Apícola',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: ambar),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF9F6F0),
          appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFE5A912),
              foregroundColor: Colors.white,
              elevation: 0),
        ),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (ctx, snap) => db.auth.currentSession == null
              ? const LoginScreen()
              : const HomeScreen(),
        ),
      );
}

// ---------------- LOGIN ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(), pass = TextEditingController();
  bool cargando = false;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> entrar() async {
    setState(() => cargando = true);
    try {
      await db.auth
          .signInWithPassword(email: email.text.trim(), password: pass.text);
    } on AuthException {
      if (mounted) aviso(context, 'Correo o contraseña incorrectos');
    }
    if (mounted) setState(() => cargando = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🐝', style: TextStyle(fontSize: 64)),
                const Text('Gestión Apícola',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cafe)),
                const SizedBox(height: 16),
                TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo')),
                TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña')),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      style: grande,
                      onPressed: cargando ? null : entrar,
                      child: Text(cargando ? 'Entrando...' : 'Iniciar sesión')),
                ),
              ]),
            ),
          ),
        ),
      );
}

// ---------------- HOME ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = const [
    InventarioScreen(),
    TrazabilidadScreen(),
    ProduccionScreen(),
    ProveedoresScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('🐝 Sistema de Gestión Apícola'),
          actions: [
            IconButton(
                tooltip: 'Cerrar sesión',
                icon: const Icon(Icons.logout),
                onPressed: () => db.auth.signOut())
          ],
        ),
        body: _pages[_currentIndex],
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          selectedItemColor: ambar,
          unselectedItemColor: Colors.grey,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2), label: 'Inventario'),
            BottomNavigationBarItem(
                icon: Icon(Icons.qr_code_scanner), label: 'Trazabilidad'),
            BottomNavigationBarItem(
                icon: Icon(Icons.analytics), label: 'Producción'),
            BottomNavigationBarItem(
                icon: Icon(Icons.agriculture), label: 'Proveedores'),
          ],
        ),
      );
}

// ================= 1. INVENTARIO (insumos con categorías personalizables) =================
class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});
  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  String? cat; // null = todos

  Future<void> editarCategoria(Map<String, dynamic>? c) async {
    final f = await formulario(
        context,
        c == null ? 'Nueva categoría' : 'Editar categoría',
        {'nombre': 'Nombre (ej. Envase, Tapa, Etiqueta)'},
        datos: c,
        eliminar: c != null);
    if (f == null) return;
    try {
      if (f.containsKey('__eliminar')) {
        await db.from('categorias').delete().eq('id', c!['id']);
        if (cat == c['id']) setState(() => cat = null);
      } else if (f['nombre']!.isNotEmpty) {
        if (c == null) {
          await db.from('categorias').insert({'nombre': f['nombre']});
        } else {
          await db
              .from('categorias')
              .update({'nombre': f['nombre']}).eq('id', c['id']);
        }
      }
    } catch (e) {
      if (mounted) aviso(context, msgError(e));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Filas>(
        stream: flujo('categorias'),
        builder: (ctx, sc) {
          final cats = sc.data ?? <Map<String, dynamic>>[];
          return StreamBuilder<Filas>(
            stream: flujo('insumos'),
            builder: (ctx, si) {
              if (!si.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = si.data!
                  .where((x) => cat == null || x['categoria_id'] == cat)
                  .toList();
              return Scaffold(
                backgroundColor: Colors.transparent,
                floatingActionButton: FloatingActionButton.extended(
                    backgroundColor: ambar,
                    onPressed: () => editarInsumo(context, cats, cat),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Insumo',
                        style: TextStyle(color: Colors.white))),
                body: Column(children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: titulo('Inventario de Insumos y Materiales')),
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                              label: const Text('Todos'),
                              selected: cat == null,
                              onSelected: (_) => setState(() => cat = null)),
                        ),
                        for (final c in cats)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onLongPress: () => editarCategoria(c),
                              child: ChoiceChip(
                                  label: Text(c['nombre']),
                                  selected: cat == c['id'],
                                  onSelected: (_) =>
                                      setState(() => cat = c['id'])),
                            ),
                          ),
                        ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: const Text('Categoría'),
                            onPressed: () => editarCategoria(null)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text(
                                'Sin insumos. Crea una categoría y agrega el primero.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                            itemCount: items.length,
                            itemBuilder: (_, k) =>
                                tarjetaInsumo(ctx, items[k], cats),
                          ),
                  ),
                ]),
              );
            },
          );
        },
      );

  Widget tarjetaInsumo(BuildContext c, Map<String, dynamic> it, Filas cats) {
    final min = (it['stock_minimo'] ?? 0) as num;
    final bajo = min > 0 && (it['existencia'] as num) <= min;
    final desc = (it['descripcion'] ?? '') as String;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(it['nombre'],
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16))),
            if (bajo) const Icon(Icons.warning_amber, color: Colors.orange),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'e'
                  ? editarInsumo(c, cats, cat, it)
                  : eliminar(c, 'insumos', it),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'e', child: Text('Editar')),
                PopupMenuItem(value: 'x', child: Text('Eliminar')),
              ],
            ),
          ]),
          if (desc.isNotEmpty)
            Text(desc, style: const TextStyle(color: Colors.black54)),
          Text('${fmt(it['existencia'])} ${it['unidad']}',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: bajo ? Colors.red : ambar)),
          if (min > 0)
            Text('Mínimo: ${fmt(min)}${bajo ? '  ·  ¡Por agotarse!' : ''}'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: FilledButton.tonalIcon(
                    style: grandeSuave,
                    onPressed: () => mover(c, 'insumos', it, -1),
                    icon: const Icon(Icons.remove),
                    label: const Text('Salida'))),
            const SizedBox(width: 8),
            Expanded(
                child: FilledButton.icon(
                    style: grande,
                    onPressed: () => mover(c, 'insumos', it, 1),
                    icon: const Icon(Icons.add),
                    label: const Text('Entrada'))),
          ]),
        ]),
      ),
    );
  }
}

Future<void> editarInsumo(BuildContext c, Filas cats, String? catSel,
    [Map<String, dynamic>? it]) async {
  final n = TextEditingController(text: it?['nombre'] ?? '');
  final u = TextEditingController(text: it?['unidad'] ?? 'pza');
  final d = TextEditingController(text: it?['descripcion'] ?? '');
  final m = TextEditingController(text: fmt(it?['stock_minimo']));
  String? cat = it != null ? it['categoria_id'] : catSel;
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(it == null ? 'Nuevo insumo' : 'Editar insumo'),
      content: StatefulBuilder(
        builder: (_, set) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: n,
                decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(
                controller: u,
                decoration:
                    const InputDecoration(labelText: 'Unidad (pza, kg, lt)')),
            TextField(
                controller: d,
                decoration:
                    const InputDecoration(labelText: 'Descripción (opcional)')),
            TextField(
                controller: m,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Stock mínimo (alerta)')),
            DropdownButtonFormField<String?>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Sin categoría')),
                for (final x in cats)
                  DropdownMenuItem<String?>(
                      value: x['id'] as String, child: Text(x['nombre'])),
              ],
              onChanged: (v) => set(() => cat = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar')),
      ],
    ),
  );
  final nombre = n.text.trim();
  final unidad = u.text.trim();
  final desc = d.text.trim();
  final minVal = num.tryParse(m.text) ?? 0;
  n.dispose();
  u.dispose();
  d.dispose();
  m.dispose();

  if (ok != true || nombre.isEmpty) return;
  final datos = {
    'nombre': nombre,
    'unidad': unidad.isEmpty ? 'pza' : unidad,
    'descripcion': desc.isEmpty ? null : desc,
    'stock_minimo': minVal,
    'categoria_id': cat,
  };
  try {
    if (it == null) {
      await db.from('insumos').insert(datos);
    } else {
      await db.from('insumos').update(datos).eq('id', it['id']);
    }
  } catch (e) {
    if (c.mounted) aviso(c, msgError(e));
  }
}

// ================= 2. TRAZABILIDAD (lotes) =================
class TrazabilidadScreen extends StatefulWidget {
  const TrazabilidadScreen({super.key});
  @override
  State<TrazabilidadScreen> createState() => _TrazabilidadScreenState();
}

class _TrazabilidadScreenState extends State<TrazabilidadScreen> {
  late Future<Filas> f = cargar();
  String busqueda = '';

  Future<Filas> cargar() => db
      .from('lotes')
      .select('*, productos(nombre, unidad)')
      .order('created_at', ascending: false);

  void detalle(Map<String, dynamic> l) => showModalBottomSheet(
        context: context,
        builder: (_) => FutureBuilder<Filas>(
          future: db
              .from('movimientos')
              .select('cantidad, insumos(nombre, unidad)')
              .eq('lote_id', l['id']),
          builder: (ctx, s) =>
              ListView(padding: const EdgeInsets.all(16), children: [
            Text('Lote ${l['codigo']}',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: ambar)),
            const SizedBox(height: 4),
            const Text('Insumos consumidos:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            if (!s.hasData) const LinearProgressIndicator(),
            for (final m in s.data ?? <Map<String, dynamic>>[])
              ListTile(
                dense: true,
                title: Text(m['insumos']['nombre']),
                trailing: Text(
                    '${fmt((m['cantidad'] as num).abs())} ${m['insumos']['unidad']}'),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(children: [
        Align(
            alignment: Alignment.centerLeft,
            child: titulo('Lotes y Seguimiento')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => busqueda = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Buscar lote o producto...',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() => f = cargar());
              await f;
            },
            child: FutureBuilder<Filas>(
              future: f,
              builder: (ctx, s) {
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final lotes = s.data!
                    .where((l) =>
                        busqueda.isEmpty ||
                        '${l['codigo']}'.toLowerCase().contains(busqueda) ||
                        '${l['productos']['nombre']}'
                            .toLowerCase()
                            .contains(busqueda))
                    .toList();
                if (lotes.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 120),
                    Center(
                        child: Text(
                            'Sin lotes. Se generan al dar salida a un producto.')),
                  ]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: lotes.length,
                  itemBuilder: (_, k) => loteCard(lotes[k]),
                );
              },
            ),
          ),
        ),
      ]);

  Widget loteCard(Map<String, dynamic> l) {
    final p = l['productos'];
    final extra = <String>[
      if (l['flora'] != null) 'Tipo de miel / flora: ${l['flora']}',
      if (l['apiario'] != null) 'Apiario de origen: ${l['apiario']}',
      if (l['nota'] != null) 'Nota: ${l['nota']}',
    ];
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => detalle(l),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(
                  child: Text(l['codigo'],
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: ambar))),
              Chip(
                label: Text('${fmt(l['cantidad'])} ${p['unidad']}',
                    style: const TextStyle(color: Colors.white)),
                backgroundColor: const Color(0xFFB45309),
              ),
            ]),
            const Divider(),
            Text('Producto: ${p['nombre']}'),
            Text('Fecha de producción: ${l['fecha']}'),
            Text(
                'Consumo recomendado: ${l['fecha_consumo_recomendado'] ?? '-'}'),
            for (final e in extra) Text(e),
            const SizedBox(height: 4),
            const Text('Toca para ver los insumos consumidos',
                style: TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

// ================= 3. PRODUCCIÓN Y ENVASADO =================
class ProduccionScreen extends StatelessWidget {
  const ProduccionScreen({super.key});

  Future<void> editar(BuildContext c, [Map<String, dynamic>? p]) async {
    final f = await formulario(
        c,
        p == null ? 'Nuevo producto' : 'Editar producto',
        {
          'nombre': 'Nombre',
          'unidad': 'Unidad (pza, kg...)',
          'codigo': 'Código para el lote (ej. MIEL1K)',
          'vida_util_meses': 'Vida útil en meses (consumo recomendado)',
        },
        datos: p ?? {'unidad': 'pza'},
        numericos: {'vida_util_meses'});
    if (f == null || f['nombre']!.isEmpty) return;
    final d = <String, dynamic>{
      'nombre': f['nombre'],
      'unidad': f['unidad']!.isEmpty ? 'pza' : f['unidad'],
      'codigo': f['codigo']!.isEmpty ? null : f['codigo']!.toUpperCase(),
      'vida_util_meses': int.tryParse(f['vida_util_meses']!),
    };
    try {
      if (p == null) {
        await db.from('productos').insert(d);
      } else {
        await db.from('productos').update(d).eq('id', p['id']);
      }
    } catch (e) {
      if (c.mounted) aviso(c, msgError(e));
    }
  }

  Future<void> darSalida(BuildContext c, Map<String, dynamic> p) async {
    final f = await formulario(
        c,
        'Salida de ${p['nombre']}',
        {
          'cantidad': 'Cantidad de piezas',
          'flora': 'Tipo de miel / flora (opcional)',
          'apiario': 'Apiario de origen (opcional)',
          'nota': 'Nota (opcional)',
        },
        numericos: {'cantidad'});
    if (f == null) return;
    final cant = num.tryParse(f['cantidad'] ?? '');
    if (cant == null || cant <= 0) return;
    try {
      final r = await db.rpc('registrar_salida_producto', params: {
        'p_producto': p['id'],
        'p_cantidad': cant,
        'p_nota': f['nota'],
        'p_flora': f['flora'],
        'p_apiario': f['apiario'],
      });
      final l = r is List ? r.first : r;
      if (!c.mounted) return;
      await showDialog(
        context: c,
        builder: (ctx) => AlertDialog(
          title: const Text('Salida registrada'),
          content: SelectableText(
              'Lote: ${l['codigo']}\nConsumo recomendado: ${l['fecha_consumo_recomendado'] ?? 'sin definir'}\n\nSe descontaron los insumos de la receta.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo'))
          ],
        ),
      );
    } catch (e) {
      if (c.mounted) {
        await showDialog(
          context: c,
          builder: (ctx) => AlertDialog(
            title: const Text('No se pudo registrar'),
            content: Text(msgError(e)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'))
            ],
          ),
        );
      }
    }
  }

  // Cuántas piezas alcanzan con el stock actual de insumos
  int? alcanza(
      String pid, Filas recetas, Map<String, Map<String, dynamic>> ins) {
    final r = recetas.where((x) => x['producto_id'] == pid).toList();
    if (r.isEmpty) return null;
    int? m;
    for (final x in r) {
      final e = (ins[x['insumo_id']]?['existencia'] ?? 0) as num;
      final n = (e / (x['cantidad'] as num)).floor();
      if (m == null || n < m) m = n;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Filas>(
        stream: flujo('productos'),
        builder: (ctx, sp) => StreamBuilder<Filas>(
          stream: flujo('insumos'),
          builder: (ctx, si) {
            if (!sp.hasData || !si.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final ins = <String, Map<String, dynamic>>{
              for (final x in si.data!) x['id'] as String: x
            };
            return FutureBuilder<Filas>(
              future: db.from('producto_insumos').select(),
              builder: (ctx, sr) {
                final recetas = sr.data ?? <Map<String, dynamic>>[];
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  floatingActionButton: FloatingActionButton.extended(
                      backgroundColor: ambar,
                      onPressed: () => editar(ctx),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('Nuevo Producto',
                          style: TextStyle(color: Colors.white))),
                  body: Column(children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: titulo('Control de Producción y Envasado')),
                    Expanded(
                      child: sp.data!.isEmpty
                          ? const Center(
                              child: Text('Sin productos. Crea el primero.'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                              itemCount: sp.data!.length,
                              itemBuilder: (_, k) =>
                                  tarjeta(ctx, sp.data![k], recetas, ins),
                            ),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      );

  Widget tarjeta(BuildContext c, Map<String, dynamic> p, Filas recetas,
      Map<String, Map<String, dynamic>> ins) {
    final a = alcanza(p['id'], recetas, ins);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(
            c, MaterialPageRoute(builder: (_) => RecetaScreen(producto: p))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(p['nombre'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: ambar))),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'e') editar(c, p);
                  if (v == 'x') eliminar(c, 'productos', p);
                  if (v == '+') mover(c, 'productos', p, 1);
                  if (v == '-') mover(c, 'productos', p, -1);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'e', child: Text('Editar')),
                  PopupMenuItem(
                      value: '+', child: Text('Entrada de existencia')),
                  PopupMenuItem(
                      value: '-', child: Text('Salida de existencia')),
                  PopupMenuItem(value: 'x', child: Text('Eliminar')),
                ],
              ),
            ]),
            Text(
                a == null
                    ? 'Sin receta (toca para agregar insumos)'
                    : 'Con el stock actual alcanza para $a ${p['unidad']}',
                style: TextStyle(
                    color: a == null || a == 0 ? Colors.red : null,
                    fontSize: 16)),
            Text('Existencia: ${fmt(p['existencia'])} ${p['unidad']}'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  style: grande,
                  onPressed: () => darSalida(c, p),
                  icon: const Icon(Icons.output),
                  label: const Text('Dar salida (genera lote)')),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- RECETA DE UN PRODUCTO ----------------
class RecetaScreen extends StatefulWidget {
  final Map<String, dynamic> producto;
  const RecetaScreen({super.key, required this.producto});
  @override
  State<RecetaScreen> createState() => _RecetaScreenState();
}

class _RecetaScreenState extends State<RecetaScreen> {
  Future<Filas> cargar() => db
      .from('producto_insumos')
      .select('insumo_id, cantidad, insumos(nombre, unidad)')
      .eq('producto_id', widget.producto['id']);

  Future<void> asignar() async {
    final Filas insumos =
        await db.from('insumos').select('id, nombre, unidad').order('nombre');
    if (!mounted) return;
    String? sel;
    final cant = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar insumo a la receta'),
        content: StatefulBuilder(
          builder: (_, set) => Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              hint: const Text('Insumo'),
              isExpanded: true,
              items: [
                for (final i in insumos)
                  DropdownMenuItem<String>(
                      value: i['id'] as String,
                      child: Text('${i['nombre']} (${i['unidad']})'))
              ],
              onChanged: (v) => set(() => sel = v),
            ),
            TextField(
                controller: cant,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Cantidad por cada pieza')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final q = double.tryParse(cant.text);
    cant.dispose();
    if (ok == true && sel != null && q != null && q > 0) {
      try {
        await db.from('producto_insumos').upsert({
          'producto_id': widget.producto['id'],
          'insumo_id': sel,
          'cantidad': q
        });
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) aviso(context, msgError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Receta: ${widget.producto['nombre']}')),
        floatingActionButton: FloatingActionButton.extended(
            backgroundColor: ambar,
            onPressed: asignar,
            icon: const Icon(Icons.add, color: Colors.white),
            label:
                const Text('Insumo', style: TextStyle(color: Colors.white))),
        body: FutureBuilder<Filas>(
          future: cargar(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.data!.isEmpty) {
              return const Center(child: Text('Sin insumos asignados'));
            }
            return ListView(children: [
              for (final r in snap.data!)
                ListTile(
                  title: Text(r['insumos']['nombre']),
                  subtitle: Text(
                      '${fmt(r['cantidad'])} ${r['insumos']['unidad']} por pieza'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      try {
                        await db
                            .from('producto_insumos')
                            .delete()
                            .eq('producto_id', widget.producto['id'])
                            .eq('insumo_id', r['insumo_id']);
                        if (mounted) setState(() {});
                      } catch (e) {
                        if (mounted) aviso(context, msgError(e));
                      }
                    },
                  ),
                ),
            ]);
          },
        ),
      );
}

// ================= 4. PROVEEDORES, UPP Y RASMIEL =================
const Map<String, String> estadosMexico = {
  '01': 'Aguascalientes',
  '02': 'Baja California',
  '03': 'Baja California Sur',
  '04': 'Campeche',
  '05': 'Coahuila',
  '06': 'Colima',
  '07': 'Chiapas',
  '08': 'Chihuahua',
  '09': 'Ciudad de México',
  '10': 'Durango',
  '11': 'Guanajuato',
  '12': 'Guerrero',
  '13': 'Hidalgo',
  '14': 'Jalisco',
  '15': 'Estado de México',
  '16': 'Michoacán',
  '17': 'Morelos',
  '18': 'Nayarit',
  '19': 'Nuevo León',
  '20': 'Oaxaca',
  '21': 'Puebla',
  '22': 'Querétaro',
  '23': 'Quintana Roo',
  '24': 'San Luis Potosí',
  '25': 'Sinaloa',
  '26': 'Sonora',
  '27': 'Tabasco',
  '28': 'Tamaulipas',
  '29': 'Tlaxcala',
  '30': 'Veracruz',
  '31': 'Yucatán',
  '32': 'Zacatecas',
};

// Catálogo rápido de claves INEGI de municipios apícolas frecuentes por estado
const Map<String, Map<String, String>> municipiosFrecuentes = {
  '01': {
    '001': 'Aguascalientes',
    '002': 'Asientos',
    '003': 'Calvillo',
    '005': 'Jesús María',
    '007': 'Rincón de Romos',
  },
  '04': {
    '002': 'Campeche',
    '003': 'Carmen',
    '004': 'Champotón',
    '006': 'Hopelchén',
    '010': 'Calakmul',
  },
  '07': {
    '019': 'Comitán de Domínguez',
    '078': 'San Cristóbal de las Casas',
    '089': 'Tapachula',
    '101': 'Tuxtla Gutiérrez',
  },
  '14': {
    '039': 'Guadalajara',
    '098': 'Tlaquepaque',
    '120': 'Zapopan',
    '124': 'Zapotlán el Grande',
  },
  '23': {
    '002': 'Felipe Carrillo Puerto',
    '004': 'Othón P. Blanco',
    '005': 'Benito Juárez',
    '006': 'José María Morelos',
  },
  '31': {
    '050': 'Mérida',
    '053': 'Motul',
    '059': 'Oxkutzcab',
    '079': 'Tekax',
    '096': 'Tizimín',
    '102': 'Valladolid',
  },
};

String generarHomoclave([Set<String> usadas = const {}]) {
  final rng = Random();
  String hc = '';
  int intentos = 0;
  do {
    hc = rng.nextInt(1000).toString().padLeft(3, '0');
    intentos++;
  } while (usadas.contains(hc) && intentos < 50);
  return hc;
}

String generarPredioAleatorio() {
  final rng = Random();
  return (rng.nextInt(999) + 1).toString().padLeft(4, '0');
}

class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});
  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> {
  String busqueda = '';

  Future<void> editarProveedor(
    BuildContext c,
    Filas existentes, [
    Map<String, dynamic>? prov,
  ]) async {
    final rasmielUsados = existentes
        .where((x) => x['id'] != prov?['id'])
        .map((x) => '${x['rasmiel']}')
        .toSet();

    String estadoSel = prov?['estado_codigo'] ?? '31';
    final munCodCtrl =
        TextEditingController(text: prov?['municipio_codigo'] ?? '050');
    final munNomCtrl =
        TextEditingController(text: prov?['municipio_nombre'] ?? 'Mérida');
    final predioCtrl = TextEditingController(
        text: prov?['predio_num'] ?? generarPredioAleatorio());
    final propCtrl =
        TextEditingController(text: prov?['propietario_num'] ?? '001');
    String homoclave = prov?['homoclave'] ?? generarHomoclave();

    final nombreCtrl = TextEditingController(text: prov?['nombre'] ?? '');
    final telCtrl = TextEditingController(text: prov?['telefono'] ?? '');
    final notaCtrl = TextEditingController(text: prov?['nota'] ?? '');

    String soloDigitos(String s) => s.trim().replaceAll(RegExp(r'[^0-9]'), '');
    String padMun() => soloDigitos(munCodCtrl.text).padLeft(3, '0');
    String padPredio() => soloDigitos(predioCtrl.text).padLeft(4, '0');
    String padProp() => soloDigitos(propCtrl.text).padLeft(3, '0');

    String construirUpp() => '$estadoSel${padMun()}${padPredio()}${padProp()}';
    String construirRasmiel() =>
        '$estadoSel${padMun()}${padPredio()}$homoclave';

    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(
            prov == null ? 'Nuevo productor / UPP' : 'Modificar productor'),
        content: StatefulBuilder(
          builder: (_, setModal) {
            final uppPreview = construirUpp();
            final rasmielPreview = construirRasmiel();
            final presets = municipiosFrecuentes[estadoSel] ?? {};

            return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // 1. Entidad federativa (2 dígitos)
                DropdownButtonFormField<String>(
                  initialValue: estadoSel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Entidad federativa (2 dígitos)'),
                  items: [
                    for (final entry in estadosMexico.entries)
                      DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text('${entry.key} - ${entry.value}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setModal(() {
                      estadoSel = v;
                      final listaMun = municipiosFrecuentes[v];
                      if (listaMun != null && listaMun.isNotEmpty) {
                        final primer = listaMun.entries.first;
                        munCodCtrl.text = primer.key;
                        munNomCtrl.text = primer.value;
                      } else {
                        munCodCtrl.text = '001';
                        munNomCtrl.text = '';
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                // 2. Municipio INEGI (3 dígitos) + selector rápido
                Row(children: [
                  SizedBox(
                    width: 115,
                    child: TextField(
                      controller: munCodCtrl,
                      maxLength: 3,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Mun. INEGI',
                        hintText: '050',
                        counterText: '',
                      ),
                      onChanged: (_) => setModal(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: munNomCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre municipio',
                        hintText: 'Ej. Mérida',
                      ),
                    ),
                  ),
                  if (presets.isNotEmpty)
                    PopupMenuButton<MapEntry<String, String>>(
                      tooltip: 'Municipios frecuentes',
                      icon: const Icon(Icons.list_alt, color: ambar),
                      onSelected: (entry) => setModal(() {
                        munCodCtrl.text = entry.key;
                        munNomCtrl.text = entry.value;
                      }),
                      itemBuilder: (_) => [
                        for (final m in presets.entries)
                          PopupMenuItem<MapEntry<String, String>>(
                            value: m,
                            child: Text('${m.key} - ${m.value}'),
                          ),
                      ],
                    ),
                ]),
                const SizedBox(height: 8),
                // 3. Predio / Consecutivo UPP (4 dígitos) y Propietario (3 dígitos)
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: predioCtrl,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Predio / UPP (4 díg.)',
                        hintText: '0142',
                        counterText: '',
                      ),
                      onChanged: (_) => setModal(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: propCtrl,
                      maxLength: 3,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Propietario (3 díg.)',
                        hintText: '001',
                        counterText: '',
                      ),
                      onChanged: (_) => setModal(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                // Vista previa de Clave UPP (12) y Clave RASMIEL (12)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F6F0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x66D97706)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Clave UPP (12 dígitos):',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.black54)),
                          Text(uppPreview,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 0.8,
                                  color: cafe)),
                          const SizedBox(height: 6),
                          Text('Clave RASMIEL (Homoclave $homoclave):',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54)),
                          Text(rasmielPreview,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 0.8,
                                  color: ambar)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Regenerar homoclave RASMIEL',
                      icon: const Icon(Icons.refresh, color: ambar),
                      onPressed: () => setModal(() {
                        String nueva;
                        int intentos = 0;
                        do {
                          nueva = generarHomoclave();
                          intentos++;
                        } while (rasmielUsados.contains(
                                '$estadoSel${padMun()}${padPredio()}$nueva') &&
                            intentos < 50);
                        homoclave = nueva;
                      }),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nombre del productor / apicultor'),
                ),
                TextField(
                  controller: telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Teléfono (opcional)'),
                ),
                TextField(
                  controller: notaCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Localidad / Nota (opcional)'),
                ),
              ]),
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ambar),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );

    final munCod = padMun();
    final munNom = munNomCtrl.text.trim();
    final predio = padPredio();
    final prop = padProp();
    final uppFinal = '$estadoSel$munCod$predio$prop';
    final rasmielFinal = '$estadoSel$munCod$predio$homoclave';
    final nombre = nombreCtrl.text.trim();
    final tel = telCtrl.text.trim();
    final nota = notaCtrl.text.trim();

    munCodCtrl.dispose();
    munNomCtrl.dispose();
    predioCtrl.dispose();
    propCtrl.dispose();
    nombreCtrl.dispose();
    telCtrl.dispose();
    notaCtrl.dispose();

    if (ok != true || nombre.isEmpty) return;

    final payload = <String, dynamic>{
      'upp_id': uppFinal,
      'rasmiel': rasmielFinal,
      'estado_codigo': estadoSel,
      'estado_nombre': estadosMexico[estadoSel] ?? '',
      'municipio_codigo': munCod,
      'municipio_nombre': munNom.isEmpty ? null : munNom,
      'predio_num': predio,
      'propietario_num': prop,
      'homoclave': homoclave,
      'nombre': nombre,
      'telefono': tel.isEmpty ? null : tel,
      'nota': nota.isEmpty ? null : nota,
    };

    try {
      if (prov == null) {
        await db.from('proveedores').insert(payload);
      } else {
        await db.from('proveedores').update(payload).eq('id', prov['id']);
      }
    } catch (e) {
      if (c.mounted) aviso(c, msgError(e));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Filas>(
        stream: flujo('proveedores'),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final todos = snap.data!;
          final lista = todos.where((p) {
            if (busqueda.isEmpty) return true;
            return '${p['nombre']}'.toLowerCase().contains(busqueda) ||
                '${p['upp_id']}'.contains(busqueda) ||
                '${p['rasmiel']}'.contains(busqueda) ||
                '${p['estado_nombre']}'.toLowerCase().contains(busqueda) ||
                '${p['municipio_nombre'] ?? ''}'
                    .toLowerCase()
                    .contains(busqueda);
          }).toList();

          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton(
              backgroundColor: ambar,
              tooltip: 'Añadir proveedor',
              onPressed: () => editarProveedor(ctx, todos),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
            body: Column(children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: titulo('Proveedores · UPP y RASMIEL')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  onChanged: (v) =>
                      setState(() => busqueda = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Buscar por productor, UPP, RASMIEL o estado...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: lista.isEmpty
                    ? const Center(
                        child: Text(
                            'Sin productores registrados. Pulsa "+" para añadir.'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        itemCount: lista.length,
                        itemBuilder: (_, k) =>
                            tarjetaProveedor(ctx, lista[k], todos),
                      ),
              ),
            ]),
          );
        },
      );

  Widget tarjetaProveedor(
    BuildContext c,
    Map<String, dynamic> p,
    Filas todos,
  ) {
    final tel = (p['telefono'] ?? '') as String;
    final nota = (p['nota'] ?? '') as String;
    final munNom = (p['municipio_nombre'] ?? '') as String;
    final ubicacion = munNom.isNotEmpty
        ? '$munNom (${p['municipio_codigo']}), ${p['estado_nombre']} (${p['estado_codigo']})'
        : 'Mun. ${p['municipio_codigo']}, ${p['estado_nombre']} (${p['estado_codigo']})';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => editarProveedor(c, todos, p),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['nombre'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: cafe),
                    ),
                    Text(ubicacion,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'e'
                    ? editarProveedor(c, todos, p)
                    : eliminar(c, 'proveedores', p),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'e', child: Text('Modificar')),
                  PopupMenuItem(value: 'x', child: Text('Eliminar')),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F6F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x59D97706)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Clave UPP (12 díg.)',
                          style:
                              TextStyle(fontSize: 11, color: Colors.black54)),
                      Text(
                          'Predio #${p['predio_num']} · Prop. ${p['propietario_num']}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                  Text('${p['upp_id']}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: cafe)),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Clave RASMIEL (SENASICA)',
                          style:
                              TextStyle(fontSize: 11, color: Colors.black54)),
                      Text('Homoclave: ${p['homoclave']}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                  Text('${p['rasmiel']}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: ambar)),
                ],
              ),
            ),
            if (tel.isNotEmpty || nota.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (tel.isNotEmpty) Text('Tel: $tel'),
              if (nota.isNotEmpty)
                Text(nota, style: const TextStyle(color: Colors.black54)),
            ],
            const SizedBox(height: 6),
            const Text('Toca el recuadro para modificar',
                style: TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

// ---------------- UTILIDADES ----------------
Future<void> mover(
    BuildContext c, String tabla, Map<String, dynamic> it, double signo) async {
  final tipo = signo > 0 ? 'Entrada' : 'Salida';
  final cant = await pedirNumero(c, '$tipo · ${it['nombre']}');
  if (cant == null) return;
  try {
    await db.from('movimientos').insert({
      (tabla == 'productos' ? 'producto_id' : 'insumo_id'): it['id'],
      'cantidad': cant * signo,
    });
  } catch (e) {
    if (c.mounted) aviso(c, msgError(e));
  }
}

Future<void> eliminar(
    BuildContext c, String tabla, Map<String, dynamic> it) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text('¿Eliminar "${it['nombre']}"?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await db.from(tabla).delete().eq('id', it['id']);
  } catch (e) {
    if (c.mounted) aviso(c, msgError(e));
  }
}

// Formulario genérico. Devuelve los textos, o {'__eliminar': '1'} si se pulsa Eliminar.
Future<Map<String, String>?> formulario(
    BuildContext c, String titulo, Map<String, String> campos,
    {Map<String, dynamic>? datos,
    bool eliminar = false,
    Set<String> numericos = const {}}) async {
  final ctrl = {
    for (final k in campos.keys)
      k: TextEditingController(text: '${datos?[k] ?? ''}')
  };
  final res = await showDialog<Map<String, String>>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in campos.entries)
            TextField(
              controller: ctrl[e.key],
              keyboardType: numericos.contains(e.key)
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(labelText: e.value),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        if (eliminar)
          TextButton(
              onPressed: () => Navigator.pop(ctx, {'__eliminar': '1'}),
              child: const Text('Eliminar')),
        FilledButton(
            onPressed: () => Navigator.pop(
                ctx, {for (final k in ctrl.keys) k: ctrl[k]!.text.trim()}),
            child: const Text('Guardar')),
      ],
    ),
  );
  for (final controller in ctrl.values) {
    controller.dispose();
  }
  return res;
}

Future<double?> pedirNumero(BuildContext c, String titulo) async {
  final t = TextEditingController();
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(
          controller: t,
          autofocus: true,
          style: const TextStyle(fontSize: 24),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Cantidad')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aceptar')),
      ],
    ),
  );
  final v = double.tryParse(t.text);
  t.dispose();
  return (ok == true && v != null && v > 0) ? v : null;
}
// Proyecto app_miel · lib/main.dart
// Antes: flutter pub add supabase_flutter
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final v = (n ?? 0) as num;
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

String msgError(Object e) {
  if (e is PostgrestException) {
    if (e.code == '23514') return 'Existencia insuficiente';
    if (e.code == '23503') {
      return 'No se puede eliminar: tiene movimientos, lotes o recetas asociados';
    }
    return e.message;
  }
  return 'Error: $e';
}

Stream<List<Map<String, dynamic>>> flujo(String t) =>
    db.from(t).stream(primaryKey: ['id']).order('nombre');

Widget titulo(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(t,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cafe)),
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
              backgroundColor: Color(0xFFE5A912), foregroundColor: Colors.white, elevation: 0),
        ),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          builder: (ctx, snap) =>
              db.auth.currentSession == null ? const LoginScreen() : const HomeScreen(),
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

  Future<void> entrar() async {
    setState(() => cargando = true);
    try {
      await db.auth.signInWithPassword(email: email.text.trim(), password: pass.text);
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
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cafe)),
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
          currentIndex: _currentIndex,
          selectedItemColor: ambar,
          unselectedItemColor: Colors.grey,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Inventario'),
            BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Trazabilidad'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Producción'),
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
          await db.from('categorias').update({'nombre': f['nombre']}).eq('id', c['id']);
        }
      }
    } catch (e) {
      if (mounted) aviso(context, msgError(e));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: flujo('categorias'),
        builder: (ctx, sc) {
          final cats = sc.data ?? [];
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: flujo('insumos'),
            builder: (ctx, si) {
              if (!si.hasData) return const Center(child: CircularProgressIndicator());
              final items =
                  si.data!.where((x) => cat == null || x['categoria_id'] == cat).toList();
              return Scaffold(
                backgroundColor: Colors.transparent,
                floatingActionButton: FloatingActionButton.extended(
                    backgroundColor: ambar,
                    onPressed: () => editarInsumo(context, cats, cat),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Insumo', style: TextStyle(color: Colors.white))),
                body: Column(children: [
                  Align(alignment: Alignment.centerLeft, child: titulo('Inventario de Insumos y Materiales')),
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                  onSelected: (_) => setState(() => cat = c['id'])),
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
                        ? const Center(child: Text('Sin insumos. Crea una categoría y agrega el primero.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                            itemCount: items.length,
                            itemBuilder: (_, k) => tarjetaInsumo(ctx, items[k], cats),
                          ),
                  ),
                ]),
              );
            },
          );
        },
      );

  Widget tarjetaInsumo(BuildContext c, Map<String, dynamic> it, List<Map<String, dynamic>> cats) {
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
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
          if (desc.isNotEmpty) Text(desc, style: const TextStyle(color: Colors.black54)),
          Text('${fmt(it['existencia'])} ${it['unidad']}',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: bajo ? Colors.red : ambar)),
          if (min > 0) Text('Mínimo: ${fmt(min)}${bajo ? '  ·  ¡Por agotarse!' : ''}'),
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

Future<void> editarInsumo(BuildContext c, List<Map<String, dynamic>> cats, String? catSel,
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
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: u, decoration: const InputDecoration(labelText: 'Unidad (pza, kg, lt)')),
            TextField(controller: d, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
            TextField(
                controller: m,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stock mínimo (alerta)')),
            DropdownButtonFormField<String?>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sin categoría')),
                for (final x in cats)
                  DropdownMenuItem<String?>(value: x['id'] as String, child: Text(x['nombre'])),
              ],
              onChanged: (v) => set(() => cat = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
      ],
    ),
  );
  if (ok != true || n.text.trim().isEmpty) return;
  final datos = {
    'nombre': n.text.trim(),
    'unidad': u.text.trim().isEmpty ? 'pza' : u.text.trim(),
    'descripcion': d.text.trim().isEmpty ? null : d.text.trim(),
    'stock_minimo': num.tryParse(m.text) ?? 0,
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
  late Future<List<Map<String, dynamic>>> f = cargar();
  String busqueda = '';

  Future<List<Map<String, dynamic>>> cargar() => db
      .from('lotes')
      .select('*, productos(nombre, unidad)')
      .order('created_at', ascending: false);

  void detalle(Map<String, dynamic> l) => showModalBottomSheet(
        context: context,
        builder: (_) => FutureBuilder<List<Map<String, dynamic>>>(
          future: db
              .from('movimientos')
              .select('cantidad, insumos(nombre, unidad)')
              .eq('lote_id', l['id']),
          builder: (ctx, s) => ListView(padding: const EdgeInsets.all(16), children: [
            Text('Lote ${l['codigo']}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ambar)),
            const SizedBox(height: 4),
            const Text('Insumos consumidos:', style: TextStyle(fontWeight: FontWeight.bold)),
            if (!s.hasData) const LinearProgressIndicator(),
            for (final m in s.data ?? [])
              ListTile(
                dense: true,
                title: Text(m['insumos']['nombre']),
                trailing: Text('${fmt((m['cantidad'] as num).abs())} ${m['insumos']['unidad']}'),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(children: [
        Align(alignment: Alignment.centerLeft, child: titulo('Lotes y Seguimiento')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => busqueda = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Buscar lote o producto...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: f,
              builder: (ctx, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final lotes = s.data!
                    .where((l) =>
                        busqueda.isEmpty ||
                        '${l['codigo']}'.toLowerCase().contains(busqueda) ||
                        '${l['productos']['nombre']}'.toLowerCase().contains(busqueda))
                    .toList();
                if (lotes.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 120),
                    Center(child: Text('Sin lotes. Se generan al dar salida a un producto.')),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(
                  child: Text(l['codigo'],
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: ambar))),
              Chip(
                label: Text('${fmt(l['cantidad'])} ${p['unidad']}',
                    style: const TextStyle(color: Colors.white)),
                backgroundColor: const Color(0xFFB45309),
              ),
            ]),
            const Divider(),
            Text('Producto: ${p['nombre']}'),
            Text('Fecha de producción: ${l['fecha']}'),
            Text('Consumo recomendado: ${l['fecha_consumo_recomendado'] ?? '-'}'),
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
    final f = await formulario(c, 'Salida de ${p['nombre']}', {
      'cantidad': 'Cantidad de piezas',
      'flora': 'Tipo de miel / flora (opcional)',
      'apiario': 'Apiario de origen (opcional)',
      'nota': 'Nota (opcional)',
    }, numericos: {'cantidad'});
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
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
        ),
      );
    } catch (e) {
      if (c.mounted) {
        await showDialog(
          context: c,
          builder: (ctx) => AlertDialog(
            title: const Text('No se pudo registrar'),
            content: Text(msgError(e)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
      }
    }
  }

  // Cuántas piezas alcanzan con el stock actual de insumos
  int? alcanza(String pid, List<Map<String, dynamic>> recetas, Map<String, Map<String, dynamic>> ins) {
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
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: flujo('productos'),
        builder: (ctx, sp) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: flujo('insumos'),
          builder: (ctx, si) {
            if (!sp.hasData || !si.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final ins = {for (final x in si.data!) x['id'] as String: x};
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: db.from('producto_insumos').select(),
              builder: (ctx, sr) {
                final recetas = sr.data ?? [];
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  floatingActionButton: FloatingActionButton.extended(
                      backgroundColor: ambar,
                      onPressed: () => editar(ctx),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text('Nuevo Producto', style: TextStyle(color: Colors.white))),
                  body: Column(children: [
                    Align(alignment: Alignment.centerLeft, child: titulo('Control de Producción y Envasado')),
                    Expanded(
                      child: sp.data!.isEmpty
                          ? const Center(child: Text('Sin productos. Crea el primero.'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                              itemCount: sp.data!.length,
                              itemBuilder: (_, k) => tarjeta(ctx, sp.data![k], recetas, ins),
                            ),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      );

  Widget tarjeta(BuildContext c, Map<String, dynamic> p, List<Map<String, dynamic>> recetas,
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(p['nombre'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16, color: ambar))),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'e') editar(c, p);
                  if (v == 'x') eliminar(c, 'productos', p);
                  if (v == '+') mover(c, 'productos', p, 1);
                  if (v == '-') mover(c, 'productos', p, -1);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'e', child: Text('Editar')),
                  PopupMenuItem(value: '+', child: Text('Entrada de existencia')),
                  PopupMenuItem(value: '-', child: Text('Salida de existencia')),
                  PopupMenuItem(value: 'x', child: Text('Eliminar')),
                ],
              ),
            ]),
            Text(
                a == null
                    ? 'Sin receta (toca para agregar insumos)'
                    : 'Con el stock actual alcanza para $a ${p['unidad']}',
                style: TextStyle(color: a == null || a == 0 ? Colors.red : null, fontSize: 16)),
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
  Future<List<Map<String, dynamic>>> cargar() => db
      .from('producto_insumos')
      .select('insumo_id, cantidad, insumos(nombre, unidad)')
      .eq('producto_id', widget.producto['id']);

  Future<void> asignar() async {
    final insumos = await db.from('insumos').select('id, nombre, unidad').order('nombre');
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
                  DropdownMenuItem(value: i['id'] as String, child: Text('${i['nombre']} (${i['unidad']})'))
              ],
              onChanged: (v) => set(() => sel = v),
            ),
            TextField(
                controller: cant,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cantidad por cada pieza')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final q = double.tryParse(cant.text);
    if (ok == true && sel != null && q != null && q > 0) {
      await db.from('producto_insumos').upsert(
          {'producto_id': widget.producto['id'], 'insumo_id': sel, 'cantidad': q});
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Receta: ${widget.producto['nombre']}')),
        floatingActionButton: FloatingActionButton.extended(
            backgroundColor: ambar,
            onPressed: asignar,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Insumo', style: TextStyle(color: Colors.white))),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: cargar(),
          builder: (ctx, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data!.isEmpty) return const Center(child: Text('Sin insumos asignados'));
            return ListView(children: [
              for (final r in snap.data!)
                ListTile(
                  title: Text(r['insumos']['nombre']),
                  subtitle: Text('${fmt(r['cantidad'])} ${r['insumos']['unidad']} por pieza'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      await db
                          .from('producto_insumos')
                          .delete()
                          .eq('producto_id', widget.producto['id'])
                          .eq('insumo_id', r['insumo_id']);
                      setState(() {});
                    },
                  ),
                ),
            ]);
          },
        ),
      );
}

// ---------------- UTILIDADES ----------------
Future<void> mover(BuildContext c, String tabla, Map<String, dynamic> it, double signo) async {
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

Future<void> eliminar(BuildContext c, String tabla, Map<String, dynamic> it) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text('¿Eliminar "${it['nombre']}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
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
    {Map<String, dynamic>? datos, bool eliminar = false, Set<String> numericos = const {}}) {
  final ctrl = {
    for (final k in campos.keys) k: TextEditingController(text: '${datos?[k] ?? ''}')
  };
  return showDialog<Map<String, String>>(
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
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        if (eliminar)
          TextButton(
              onPressed: () => Navigator.pop(ctx, {'__eliminar': '1'}),
              child: const Text('Eliminar')),
        FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, {for (final k in ctrl.keys) k: ctrl[k]!.text.trim()}),
            child: const Text('Guardar')),
      ],
    ),
  );
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
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceptar')),
      ],
    ),
  );
  final v = double.tryParse(t.text);
  return (ok == true && v != null && v > 0) ? v : null;
}
// Proyecto app_miel · lib/main.dart
// Antes: flutter pub add supabase_flutter
// Requiere haber ejecutado sql.sql en Supabase (tablas, triggers, vista y RPC).
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
    url: 'https://vidgleezpxlayvsfbkho.supabase.co',
    publishableKey: 'sb_publishable__mR07ze-8jIZEnEyXrKpUg_hbWGs9GY',
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

/// Convierte texto a número aceptando coma o punto decimal.
num? parseNum(String s) => num.tryParse(s.trim().replaceAll(',', '.'));

/// Texto vacío -> null (para no guardar '' en la base de datos).
String? vacioNull(String? s) {
  final t = (s ?? '').trim();
  return t.isEmpty ? null : t;
}

/// Libera controladores DESPUÉS de que termina la animación del diálogo.
/// (Liberarlos justo al cerrar provoca "TextEditingController used after
/// being disposed".)
void liberar(List<ChangeNotifier> items) {
  Future.delayed(const Duration(milliseconds: 500), () {
    for (final x in items) {
      x.dispose();
    }
  });
}

String msgError(Object e) {
  if (e is PostgrestException) {
    final t = '${e.message} ${e.details ?? ''}';
    switch (e.code) {
      case '23514':
        if (t.contains('existencia')) return 'Existencia insuficiente';
        if (t.contains('proveedores_claves_coherentes')) {
          return 'La clave UPP/RASMIEL no coincide con estado, municipio y predio';
        }
        if (t.contains('proveedores_estado')) {
          return 'Entidad federativa inválida (01 a 32)';
        }
        if (t.contains('insumos_miel_unidad')) {
          return 'La miel debe tener unidad kg o g';
        }
        return 'Dato fuera de rango o con formato inválido';
      case '23503':
        if (t.contains('is not present')) {
          return 'El registro relacionado ya no existe';
        }
        return 'No se puede eliminar: tiene movimientos, lotes o recetas asociados';
      case '23505':
        if (t.contains('rasmiel')) return 'Ya existe esa Clave RASMIEL';
        if (t.contains('upp_id')) return 'Ya existe un proveedor con esa Clave UPP';
        if (t.contains('categorias')) return 'Ya existe una categoría con ese nombre';
        if (t.contains('codigo')) return 'Ya existe un registro con ese ID / código';
        return 'Ya existe un registro igual';
      case '42501':
        return 'Sin permiso. Cierra sesión y vuelve a entrar';
      case 'PGRST202':
      case '42883':
        return 'Falta una función en la base de datos. Ejecuta el archivo sql.sql';
      case '42P01':
        return 'Falta una tabla o vista. Ejecuta el archivo sql.sql';
    }
    return e.message;
  }
  if (e is AuthException) return e.message;
  final s = '$e';
  if (s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('XMLHttpRequest')) {
    return 'Sin conexión. Revisa tu internet e inténtalo de nuevo';
  }
  return 'Error: $e';
}

Stream<Filas> flujo(String t) =>
    db.from(t).stream(primaryKey: ['id']).order('nombre');

/// Devuelve un widget de "cargando" o "error" mientras no haya datos; null si ya hay.
Widget? pendiente(AsyncSnapshot s, [VoidCallback? reintentar]) {
  if (s.hasError) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('No se pudo cargar.\n${msgError(s.error!)}',
              textAlign: TextAlign.center),
          if (reintentar != null)
            TextButton(onPressed: reintentar, child: const Text('Reintentar')),
        ]),
      ),
    );
  }
  if (!s.hasData) return const Center(child: CircularProgressIndicator());
  return null;
}

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
    final correo = email.text.trim();
    if (correo.isEmpty || pass.text.isEmpty) {
      aviso(context, 'Escribe tu correo y contraseña');
      return;
    }
    setState(() => cargando = true);
    try {
      await db.auth.signInWithPassword(email: correo, password: pass.text);
    } on AuthException catch (e) {
      if (mounted) {
        aviso(
            context,
            e.message.toLowerCase().contains('invalid')
                ? 'Correo o contraseña incorrectos'
                : e.message);
      }
    } catch (e) {
      // Sin internet u otro fallo: antes el botón se quedaba bloqueado
      if (mounted) aviso(context, msgError(e));
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
                    onSubmitted: (_) => cargando ? null : entrar(),
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
// Orden de pestañas: 1.Proveedores  2.Insumos  3.Producto  4.Trazabilidad
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = const [
    ProveedoresScreen(),
    InventarioScreen(),
    ProduccionScreen(),
    TrazabilidadScreen(),
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
                icon: Icon(Icons.agriculture), label: 'Proveedores'),
            BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2), label: 'Insumos'),
            BottomNavigationBarItem(
                icon: Icon(Icons.shopping_basket), label: 'Producto'),
            BottomNavigationBarItem(
                icon: Icon(Icons.qr_code_scanner), label: 'Trazabilidad'),
          ],
        ),
      );
}

// ================= 1. PROVEEDORES, UPP Y RASMIEL =================
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

// Catálogo interno de municipios con clave INEGI (3 dígitos), una línea por
// municipio: "clave nombre".
//  * Completos: Aguascalientes, Baja California, Baja California Sur, Campeche,
//    Colima, Ciudad de México, Morelos, Nayarit, Querétaro, Quintana Roo,
//    Tabasco y Yucatán.
//  * Resto de estados: capital y principales municipios.
// Para completarlos con el catálogo oficial completo, importa el CSV del INEGI
// a la tabla "municipios" de Supabase (ver sql.sql): se mezcla solo y tiene
// prioridad sobre este listado. La clave siempre se puede teclear a mano.
const Map<String, String> municipiosBase = {
  '01': '''001 Aguascalientes
002 Asientos
003 Calvillo
004 Cosío
005 Jesús María
006 Pabellón de Arteaga
007 Rincón de Romos
008 San José de Gracia
009 Tepezalá
010 El Llano
011 San Francisco de los Romo''',
  '02': '''001 Ensenada
002 Mexicali
003 Tecate
004 Tijuana
005 Playas de Rosarito
006 San Quintín
007 San Felipe''',
  '03': '''001 Comondú
002 Mulegé
003 La Paz
008 Los Cabos
009 Loreto''',
  '04': '''001 Calkiní
002 Campeche
003 Carmen
004 Champotón
005 Hecelchakán
006 Hopelchén
007 Palizada
008 Tenabo
009 Escárcega
010 Calakmul
011 Candelaria
012 Seybaplaya
013 Dzitbalché''',
  '05': '''002 Acuña
017 Matamoros
018 Monclova
025 Piedras Negras
030 Saltillo
035 Torreón''',
  '06': '''001 Armería
002 Colima
003 Comala
004 Coquimatlán
005 Cuauhtémoc
006 Ixtlahuacán
007 Manzanillo
008 Minatitlán
009 Tecomán
010 Villa de Álvarez''',
  '07': '''019 Comitán de Domínguez
027 Chiapa de Corzo
059 Ocosingo
065 Palenque
078 San Cristóbal de las Casas
089 Tapachula
101 Tuxtla Gutiérrez''',
  '08': '''017 Delicias
019 Chihuahua
021 Cuauhtémoc
032 Hidalgo del Parral
037 Juárez''',
  '09': '''002 Azcapotzalco
003 Coyoacán
004 Cuajimalpa de Morelos
005 Gustavo A. Madero
006 Iztacalco
007 Iztapalapa
008 La Magdalena Contreras
009 Milpa Alta
010 Álvaro Obregón
011 Tláhuac
012 Tlalpan
013 Xochimilco
014 Benito Juárez
015 Cuauhtémoc
016 Miguel Hidalgo
017 Venustiano Carranza''',
  '10': '''005 Durango
007 Gómez Palacio
012 Lerdo''',
  '11': '''003 San Miguel de Allende
007 Celaya
015 Guanajuato
017 Irapuato
020 León
027 Salamanca
037 Silao de la Victoria''',
  '12': '''001 Acapulco de Juárez
029 Chilpancingo de los Bravo''',
  '13': '''048 Pachuca de Soto
077 Tulancingo de Bravo''',
  '14': '''006 Ameca
008 Autlán de Navarro
018 Chapala
023 Zapotlán el Grande
039 Guadalajara
053 Lagos de Moreno
063 Ocotlán
067 Puerto Vallarta
070 El Salto
093 Tepatitlán de Morelos
094 Tequila
097 Tlajomulco de Zúñiga
098 San Pedro Tlaquepaque
101 Tonalá
120 Zapopan
124 Zapotlanejo''',
  '15': '''025 Chalco
033 Ecatepec de Morelos
054 Metepec
057 Naucalpan de Juárez
058 Nezahualcóyotl
099 Texcoco
104 Tlalnepantla de Baz
106 Toluca
110 Valle de Bravo
121 Cuautitlán Izcalli''',
  '16': '''006 Apatzingán
052 Lázaro Cárdenas
053 Morelia
066 Pátzcuaro
102 Uruapan
108 Zamora
112 Zitácuaro''',
  '17': '''001 Amacuzac
002 Atlatlahucan
003 Axochiapan
004 Ayala
005 Coatlán del Río
006 Cuautla
007 Cuernavaca
008 Emiliano Zapata
009 Huitzilac
010 Jantetelco
011 Jiutepec
012 Jojutla
013 Jonacatepec
014 Mazatepec
015 Miacatlán
016 Ocuituco
017 Puente de Ixtla
018 Temixco
019 Tepalcingo
020 Tepoztlán
021 Tetecala
022 Tetela del Volcán
023 Tlalnepantla
024 Tlaltizapán de Zapata
025 Tlaquiltenango
026 Tlayacapan
027 Totolapan
028 Xochitepec
029 Yautepec
030 Yecapixtla
031 Zacatepec
032 Zacualpan de Amilpas
033 Temoac
034 Coatetelco
035 Xoxocotla
036 Hueyapan''',
  '18': '''001 Acaponeta
002 Ahuacatlán
003 Amatlán de Cañas
004 Compostela
005 Huajicori
006 Ixtlán del Río
007 Jala
008 Xalisco
009 Del Nayar
010 Rosamorada
011 Ruíz
012 San Blas
013 San Pedro Lagunillas
014 Santa María del Oro
015 Santiago Ixcuintla
016 Tecuala
017 Tepic
018 Tuxpan
019 La Yesca
020 Bahía de Banderas''',
  '19': '''006 Apodaca
019 San Pedro Garza García
021 General Escobedo
024 Linares
026 Guadalupe
039 Monterrey
046 San Nicolás de los Garza
048 Santa Catarina''',
  '20': '''039 Huajuapan de León
043 Juchitán de Zaragoza
067 Oaxaca de Juárez
079 Salina Cruz''',
  '21': '''019 Atlixco
048 Cuetzalan del Progreso
071 Huauchinango
114 Puebla
119 San Andrés Cholula
132 San Martín Texmelucan
140 San Pedro Cholula
156 Tehuacán
174 Teziutlán
208 Zacatlán''',
  '22': '''001 Amealco de Bonfil
002 Pinal de Amoles
003 Arroyo Seco
004 Cadereyta de Montes
005 Colón
006 Corregidora
007 Ezequiel Montes
008 Huimilpan
009 Jalpan de Serra
010 Landa de Matamoros
011 El Marqués
012 Pedro Escobedo
013 Peñamiller
014 Querétaro
015 San Joaquín
016 San Juan del Río
017 Tequisquiapan
018 Tolimán''',
  '23': '''001 Cozumel
002 Felipe Carrillo Puerto
003 Isla Mujeres
004 Othón P. Blanco
005 Benito Juárez
006 José María Morelos
007 Lázaro Cárdenas
008 Solidaridad
009 Tulum
010 Bacalar
011 Puerto Morelos''',
  '24': '''013 Ciudad Valles
028 San Luis Potosí
035 Soledad de Graciano Sánchez''',
  '25': '''001 Ahome
006 Culiacán
011 Guasave
012 Mazatlán
018 Navolato''',
  '26': '''002 Agua Prieta
018 Cajeme
029 Guaymas
030 Hermosillo
042 Navojoa
043 Nogales
055 San Luis Río Colorado''',
  '27': '''001 Balancán
002 Cárdenas
003 Centla
004 Centro
005 Comalcalco
006 Cunduacán
007 Emiliano Zapata
008 Huimanguillo
009 Jalapa
010 Jalpa de Méndez
011 Jonuta
012 Macuspana
013 Nacajuca
014 Paraíso
015 Tacotalpa
016 Teapa
017 Tenosique''',
  '28': '''003 Altamira
009 Ciudad Madero
022 Matamoros
027 Nuevo Laredo
032 Reynosa
038 Tampico
041 Victoria''',
  '29': '''005 Apizaco
033 Tlaxcala''',
  '30': '''028 Boca del Río
038 Coatepec
039 Coatzacoalcos
044 Córdoba
087 Xalapa
102 Martínez de la Torre
108 Minatitlán
118 Orizaba
124 Papantla
131 Poza Rica de Hidalgo
141 San Andrés Tuxtla
189 Tuxpan
193 Veracruz''',
  '31': '''001 Abalá
002 Acanceh
003 Akil
004 Baca
005 Bokobá
006 Buctzotz
007 Cacalchén
008 Calotmul
009 Cansahcab
010 Cantamayec
011 Celestún
012 Cenotillo
013 Conkal
014 Cuncunul
015 Cuzamá
016 Chacsinkín
017 Chankom
018 Chapab
019 Chemax
020 Chicxulub Pueblo
021 Chichimilá
022 Chikindzonot
023 Chocholá
024 Chumayel
025 Dzán
026 Dzemul
027 Dzidzantún
028 Dzilam de Bravo
029 Dzilam González
030 Dzitás
031 Dzoncauich
032 Espita
033 Halachó
034 Hocabá
035 Hoctún
036 Homún
037 Huhí
038 Hunucmá
039 Ixil
040 Izamal
041 Kanasín
042 Kantunil
043 Kaua
044 Kinchil
045 Kopomá
046 Mama
047 Maní
048 Maxcanú
049 Mayapán
050 Mérida
051 Mocochá
052 Motul
053 Muna
054 Muxupip
055 Opichén
056 Oxkutzcab
057 Panabá
058 Peto
059 Progreso
060 Quintana Roo
061 Río Lagartos
062 Sacalum
063 Samahil
064 Sanahcat
065 San Felipe
066 Santa Elena
067 Seyé
068 Sinanché
069 Sotuta
070 Sucilá
071 Sudzal
072 Suma
073 Tahdziú
074 Tahmek
075 Teabo
076 Tecoh
077 Tekal de Venegas
078 Tekantó
079 Tekax
080 Tekit
081 Tekom
082 Telchac Pueblo
083 Telchac Puerto
084 Temax
085 Temozón
086 Tepakán
087 Tetiz
088 Teya
089 Ticul
090 Timucuy
091 Tinum
092 Tixcacalcupul
093 Tixkokob
094 Tixmehuac
095 Tixpéual
096 Tizimín
097 Tunkás
098 Tzucacab
099 Uayma
100 Ucú
101 Umán
102 Valladolid
103 Xocchel
104 Yaxcabá
105 Yaxkukul
106 Yobaín''',
  '32': '''010 Fresnillo
017 Guadalupe
056 Zacatecas''',
};

Map<String, String> _parseMun(String? txt) {
  final r = <String, String>{};
  if (txt == null) return r;
  for (final l in txt.split('\n')) {
    final s = l.trim();
    if (s.length < 5) continue;
    r[s.substring(0, 3)] = s.substring(4).trim();
  }
  return r;
}

final Map<String, Map<String, String>> _municipiosDb = {};

/// Municipios de un estado: catálogo interno + lo que haya en la tabla
/// "municipios" de Supabase (esa tiene prioridad). Si la tabla no existe o
/// falla la red, se usa solo el catálogo interno.
Future<Map<String, String>> municipiosDe(String ent) async {
  final base = _parseMun(municipiosBase[ent]);
  final cache = _municipiosDb[ent];
  if (cache != null) return {...base, ...cache};
  try {
    final r = await db
        .from('municipios')
        .select('cve_mun, nombre')
        .eq('cve_ent', ent)
        .order('cve_mun')
        .limit(1000);
    final m = <String, String>{
      for (final x in r) '${x['cve_mun']}': '${x['nombre']}'
    };
    _municipiosDb[ent] = m;
    return {...base, ...m};
  } catch (_) {
    return base;
  }
}

/// Selector con buscador para elegir municipio (hay estados con cientos).
Future<MapEntry<String, String>?> elegirMunicipio(
    BuildContext c, String estado, Map<String, String> cat) {
  String q = '';
  return showDialog<MapEntry<String, String>>(
    context: c,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final items = cat.entries
          .where((e) =>
              q.isEmpty || e.value.toLowerCase().contains(q) || e.key.contains(q))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return AlertDialog(
        title: Text('Municipios · $estado'),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar municipio o clave'),
              onChanged: (v) => set(() => q = v.trim().toLowerCase()),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                          'Sin coincidencias.\nEscribe la clave a mano.',
                          textAlign: TextAlign.center))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        title: Text(items[i].value),
                        trailing: Text(items[i].key),
                        onTap: () => Navigator.pop(ctx, items[i]),
                      ),
                    ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))
        ],
      );
    }),
  );
}

String generarHomoclave() => Random().nextInt(1000).toString().padLeft(3, '0');

String generarPredioAleatorio() =>
    (Random().nextInt(999) + 1).toString().padLeft(4, '0');

/// Diálogo de alta / edición de proveedor. Devuelve el payload listo para
/// guardar, o null si se cancela.
class _ProveedorDialog extends StatefulWidget {
  final Map<String, dynamic>? prov;
  final Set<String> rasmielUsados;
  final Set<String> uppUsados;
  const _ProveedorDialog(
      {required this.prov,
      required this.rasmielUsados,
      required this.uppUsados});
  @override
  State<_ProveedorDialog> createState() => _ProveedorDialogState();
}

class _ProveedorDialogState extends State<_ProveedorDialog> {
  late String estadoSel;
  late String homoclave;
  late final TextEditingController munCod,
      munNom,
      predio,
      prop,
      uppManual,
      nombre,
      tel,
      nota,
      otro,
      otroNom,
      idProd;
  bool manual = false;
  Map<String, String> catMun = {};

  static final _soloDigitos = RegExp(r'[^0-9]');
  String _dig(String s) => s.replaceAll(_soloDigitos, '');
  String get munC => _dig(munCod.text).padLeft(3, '0');
  String get predioC => _dig(predio.text).padLeft(4, '0');
  String get propC => _dig(prop.text).padLeft(3, '0');
  String get upp => '$estadoSel$munC$predioC$propC';
  String get rasmiel => '$estadoSel$munC$predioC$homoclave';

  @override
  void initState() {
    super.initState();
    final p = widget.prov;
    estadoSel = '${p?['estado_codigo'] ?? '31'}';
    munCod = TextEditingController(text: '${p?['municipio_codigo'] ?? '050'}');
    munNom = TextEditingController(
        text: '${p?['municipio_nombre'] ?? (p == null ? 'Mérida' : '')}');
    predio = TextEditingController(
        text: '${p?['predio_num'] ?? generarPredioAleatorio()}');
    prop = TextEditingController(text: '${p?['propietario_num'] ?? '001'}');
    uppManual = TextEditingController(text: '${p?['upp_id'] ?? ''}');
    nombre = TextEditingController(text: '${p?['nombre'] ?? ''}');
    tel = TextEditingController(text: '${p?['telefono'] ?? ''}');
    nota = TextEditingController(text: '${p?['nota'] ?? ''}');
    otro = TextEditingController(text: '${p?['upp_otro'] ?? ''}');
    otroNom = TextEditingController(text: '${p?['upp_otro_nombre'] ?? ''}');
    idProd = TextEditingController(text: '${p?['id_productor'] ?? ''}');
    homoclave = '${p?['homoclave'] ?? generarHomoclave()}';
    if (p == null) _homoclaveLibre();
    _cargarCatalogo();
  }

  @override
  void dispose() {
    for (final x in [
      munCod, munNom, predio, prop, uppManual, nombre, tel, nota, otro,
      otroNom, idProd
    ]) {
      x.dispose();
    }
    super.dispose();
  }

  void _homoclaveLibre() {
    String h;
    int i = 0;
    do {
      h = generarHomoclave();
      i++;
    } while (widget.rasmielUsados.contains('$estadoSel$munC$predioC$h') &&
        i < 500);
    homoclave = h;
  }

  Future<void> _cargarCatalogo({bool elegirPrimero = false}) async {
    final est = estadoSel;
    final m = await municipiosDe(est);
    if (!mounted || est != estadoSel) return;
    setState(() {
      catMun = m;
      if (elegirPrimero) {
        final k = m.keys.toList()..sort();
        munCod.text = k.isEmpty ? '001' : k.first;
        munNom.text = k.isEmpty ? '' : m[k.first]!;
      } else if (munNom.text.trim().isEmpty) {
        munNom.text = m[munCod.text] ?? '';
      }
    });
  }

  // Modo manual: descompone los 12 dígitos en entidad / municipio / predio / propietario
  void _aplicarManual() {
    final t = uppManual.text;
    if (t.length != 12) return;
    final e = t.substring(0, 2);
    if (!estadosMexico.containsKey(e)) return;
    final cambio = e != estadoSel;
    estadoSel = e;
    munCod.text = t.substring(2, 5);
    predio.text = t.substring(5, 9);
    prop.text = t.substring(9, 12);
    munNom.text = catMun[munCod.text] ?? '';
    if (cambio) {
      catMun = {};
      _cargarCatalogo();
    }
  }

  bool get _manualOk {
    final t = uppManual.text;
    return t.length == 12 &&
        estadosMexico.containsKey(t.substring(0, 2)) &&
        t.substring(2, 5) != '000' &&
        t.substring(5, 9) != '0000' &&
        t.substring(9, 12) != '000';
  }

  bool get _structOk =>
      munCod.text.isNotEmpty &&
      predio.text.isNotEmpty &&
      prop.text.isNotEmpty &&
      munC != '000' &&
      predioC != '0000' &&
      propC != '000';

  bool get _otroOk => otro.text.isEmpty || otro.text.length == 12;
  bool get _uppDuplicada => widget.uppUsados.contains(upp);
  bool get _valido =>
      nombre.text.trim().isNotEmpty &&
      (manual ? _manualOk : _structOk) &&
      !_uppDuplicada &&
      _otroOk;

  void _guardar() {
    var hc = homoclave;
    final usados = widget.rasmielUsados;
    String rs(String h) => '$estadoSel$munC$predioC$h';
    if (usados.contains(rs(hc))) {
      // Esa combinación ya existe: busca otra homoclave libre
      String n;
      int i = 0;
      do {
        n = generarHomoclave();
        i++;
      } while (usados.contains(rs(n)) && i < 500);
      if (usados.contains(rs(n))) {
        aviso(context, 'No hay homoclave libre para ese predio');
        return;
      }
      hc = n;
    }
    final otroTxt = vacioNull(otro.text);
    Navigator.pop(context, <String, dynamic>{
      'upp_id': upp,
      'rasmiel': rs(hc),
      'estado_codigo': estadoSel,
      'estado_nombre': estadosMexico[estadoSel] ?? '',
      'municipio_codigo': munC,
      'municipio_nombre': vacioNull(munNom.text),
      'predio_num': predioC,
      'propietario_num': propC,
      'homoclave': hc,
      'nombre': nombre.text.trim(),
      'telefono': vacioNull(tel.text),
      'nota': vacioNull(nota.text),
      'upp_otro': otroTxt,
      'upp_otro_nombre': otroTxt == null ? null : vacioNull(otroNom.text),
      'id_productor': vacioNull(idProd.text)?.toUpperCase(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final nombreEstado = estadosMexico[estadoSel] ?? '';
    return AlertDialog(
      title: Text(
          widget.prov == null ? 'Nuevo productor / UPP' : 'Modificar productor'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ingresar UPP manualmente'),
            subtitle: const Text('Escribe los 12 dígitos directamente'),
            value: manual,
            onChanged: (v) => setState(() {
              manual = v;
              if (v) uppManual.text = upp;
            }),
          ),
          if (manual) ...[
            TextField(
              controller: uppManual,
              maxLength: 12,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Clave UPP (12 dígitos)',
                helperText: 'Entidad(2) + Municipio(3) + Predio(4) + Propietario(3)',
                counterText: '',
                errorText: uppManual.text.isEmpty || _manualOk
                    ? null
                    : 'UPP inválida: 12 dígitos, entidad 01-32 y sin bloques en cero',
              ),
              onChanged: (_) => setState(_aplicarManual),
            ),
            if (_manualOk)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                      '$estadoSel $nombreEstado · Mun. $munC · Predio $predioC · Prop. $propC',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
              ),
            TextField(
              controller: munNom,
              decoration: const InputDecoration(
                  labelText: 'Nombre municipio (opcional)'),
            ),
          ] else ...[
            // 1. Entidad federativa (2 dígitos)
            DropdownButtonFormField<String>(
              key: ValueKey(estadoSel),
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
                setState(() {
                  estadoSel = v;
                  catMun = {};
                  munCod.text = '001';
                  munNom.text = '';
                });
                _cargarCatalogo(elegirPrimero: true);
              },
            ),
            const SizedBox(height: 8),
            // 2. Municipio INEGI (3 dígitos) + buscador
            Row(children: [
              SizedBox(
                width: 105,
                child: TextField(
                  controller: munCod,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Mun. INEGI',
                    hintText: '050',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {
                    if (munCod.text.length == 3 &&
                        catMun[munCod.text] != null) {
                      munNom.text = catMun[munCod.text]!;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: munNom,
                  decoration: const InputDecoration(
                    labelText: 'Nombre municipio',
                    hintText: 'Ej. Mérida',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Buscar municipio (${catMun.length})',
                icon: const Icon(Icons.search, color: ambar),
                onPressed: () async {
                  final r = await elegirMunicipio(context, nombreEstado, catMun);
                  if (r == null || !mounted) return;
                  setState(() {
                    munCod.text = r.key;
                    munNom.text = r.value;
                  });
                },
              ),
            ]),
            const SizedBox(height: 8),
            // 3. Predio / Consecutivo UPP (4 dígitos) y Propietario (3 dígitos)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: predio,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Predio / UPP (4 díg.)',
                    hintText: '0142',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: prop,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Propietario (3 díg.)',
                    hintText: '001',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ],
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
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                    Text(upp,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.8,
                            color: cafe)),
                    if (_uppDuplicada)
                      const Text('Ya existe un proveedor con esta UPP',
                          style: TextStyle(fontSize: 12, color: Colors.red)),
                    const SizedBox(height: 6),
                    Text('Clave RASMIEL (Homoclave $homoclave):',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54)),
                    Text(rasmiel,
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
                onPressed: () => setState(_homoclaveLibre),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nombre,
            decoration: InputDecoration(
              labelText: 'Nombre del productor / apicultor',
              errorText: nombre.text.trim().isEmpty ? 'Obligatorio' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: idProd,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))
            ],
            decoration: const InputDecoration(
                labelText: 'ID de productor (opcional)',
                helperText: 'Solo letras y números'),
          ),
          TextField(
            controller: tel,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
          ),
          TextField(
            controller: otro,
            maxLength: 12,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'UPP de otro (opcional)',
              helperText: 'Granja externa, con abejas ajenas',
              counterText: '',
              errorText: _otroOk ? null : 'Deben ser 12 dígitos',
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: otroNom,
            decoration:
                const InputDecoration(labelText: 'Dueño de esa UPP (opcional)'),
          ),
          TextField(
            controller: nota,
            decoration: const InputDecoration(
                labelText: 'Localidad / Nota (opcional)'),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ambar),
            onPressed: _valido ? _guardar : null,
            child: const Text('Guardar')),
      ],
    );
  }
}

class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});
  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> {
  String busqueda = '';
  Stream<Filas> _s = flujo('proveedores');

  Future<void> editarProveedor(
    BuildContext c,
    Filas existentes, [
    Map<String, dynamic>? prov,
  ]) async {
    final otros = existentes.where((x) => x['id'] != prov?['id']);
    final payload = await showDialog<Map<String, dynamic>>(
      context: c,
      builder: (_) => _ProveedorDialog(
        prov: prov,
        rasmielUsados: {for (final x in otros) '${x['rasmiel']}'},
        uppUsados: {for (final x in otros) '${x['upp_id']}'},
      ),
    );
    if (payload == null) return;
    try {
      if (prov == null) {
        await db.from('proveedores').insert(payload);
      } else {
        await db.from('proveedores').update(payload).eq('id', prov['id']);
      }
      if (c.mounted) aviso(c, 'Productor guardado');
    } catch (e) {
      if (c.mounted) aviso(c, msgError(e));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Filas>(
        stream: _s,
        builder: (ctx, snap) {
          final espera =
              pendiente(snap, () => setState(() => _s = flujo('proveedores')));
          if (espera != null) return espera;
          final todos = snap.data!;
          final lista = todos.where((p) {
            if (busqueda.isEmpty) return true;
            return '${p['nombre']}'.toLowerCase().contains(busqueda) ||
                '${p['upp_id']}'.contains(busqueda) ||
                '${p['upp_otro'] ?? ''}'.contains(busqueda) ||
                '${p['rasmiel']}'.contains(busqueda) ||
                '${p['id_productor'] ?? ''}'.toLowerCase().contains(busqueda) ||
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
            if (p['id_productor'] != null) ...[
              const SizedBox(height: 8),
              Text('ID de productor: ${p['id_productor']}'),
            ],
            if (p['upp_otro'] != null) ...[
              const SizedBox(height: 8),
              Text(
                  'UPP de otro: ${p['upp_otro']} ${p['upp_otro_nombre'] ?? ''}'),
            ],
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

// ================= 2. INSUMOS (categorías personalizables) =================
class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});
  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  String? cat; // null = todos
  // Los streams se crean una sola vez (antes se recreaban en cada rebuild)
  Stream<Filas> _sCats = flujo('categorias');
  Stream<Filas> _sIns = flujo('insumos');

  Future<void> editarCategoria(Map<String, dynamic>? c) async {
    final f = await formulario(
        context,
        c == null ? 'Nueva categoría' : 'Editar categoría',
        {'nombre': 'Nombre (ej. Envase, Tapa, Etiqueta)'},
        datos: c,
        eliminar: c != null,
        requeridos: {'nombre'});
    if (f == null) return;
    try {
      if (f.containsKey('__eliminar')) {
        await db.from('categorias').delete().eq('id', c!['id']);
        if (cat == c['id'] && mounted) setState(() => cat = null);
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
        stream: _sCats,
        builder: (ctx, sc) {
          final cats = sc.data ?? <Map<String, dynamic>>[];
          return StreamBuilder<Filas>(
            stream: _sIns,
            builder: (ctx, si) {
              final espera = pendiente(
                  si,
                  () => setState(() {
                        _sCats = flujo('categorias');
                        _sIns = flujo('insumos');
                      }));
              if (espera != null) return espera;
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
    final miel = it['es_miel'] == true;
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
            if (miel) const Text('🍯 ', style: TextStyle(fontSize: 16)),
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
  String? cat = it != null ? it['categoria_id'] as String? : catSel;
  bool esMiel = it?['es_miel'] == true;
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final un = u.text.trim().toLowerCase();
      final unidadOk = !esMiel || un == 'kg' || un == 'g';
      final valido = n.text.trim().isNotEmpty && unidadOk;
      return AlertDialog(
        title: Text(it == null ? 'Nuevo insumo' : 'Editar insumo'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: n,
                onChanged: (_) => set(() {}),
                decoration: InputDecoration(
                    labelText: 'Nombre',
                    errorText: n.text.trim().isEmpty ? 'Obligatorio' : null)),
            TextField(
                controller: u,
                onChanged: (_) => set(() {}),
                decoration: InputDecoration(
                    labelText: 'Unidad (pza, kg, lt)',
                    errorText: unidadOk ? null : 'La miel debe ir en kg o g')),
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Es miel'),
              subtitle: const Text('Genera clave de trazabilidad (unidad kg o g)'),
              value: esMiel,
              onChanged: (v) => set(() => esMiel = v),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: valido ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Guardar')),
        ],
      );
    }),
  );
  final nombre = n.text.trim();
  final unidad = u.text.trim().toLowerCase();
  final desc = d.text.trim();
  final minVal = parseNum(m.text) ?? 0;
  liberar([n, u, d, m]);

  if (ok != true || nombre.isEmpty) return;
  if (minVal < 0) {
    if (c.mounted) aviso(c, 'El stock mínimo no puede ser negativo');
    return;
  }
  final datos = {
    'nombre': nombre,
    'unidad': unidad.isEmpty ? 'pza' : unidad,
    'descripcion': desc.isEmpty ? null : desc,
    'stock_minimo': minVal,
    'categoria_id': cat,
    'es_miel': esMiel,
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

// ================= 3. PRODUCTO (producción, envasado y receta) =================

/// Cantidad de insumo por cada pieza del producto.
/// * Miel: sale del gramaje del producto (convertido a la unidad del insumo).
/// * Resto: la cantidad definida en la receta.
/// Devuelve null si no se puede calcular (miel sin gramaje o sin unidad kg/g).
double? porPieza(Map<String, dynamic> p, Map<String, dynamic>? ins, num cantReceta) {
  if (ins?['es_miel'] == true) {
    final g = p['gramaje'];
    if (g == null) return null;
    final gramos = (g as num).toDouble() * ('${p['gramaje_unidad']}' == 'kg' ? 1000 : 1);
    final u = '${ins?['unidad'] ?? ''}'.trim().toLowerCase();
    if (u == 'kg') return gramos / 1000;
    if (u == 'g') return gramos;
    return null;
  }
  return cantReceta.toDouble();
}

class ProduccionScreen extends StatefulWidget {
  const ProduccionScreen({super.key});
  @override
  State<ProduccionScreen> createState() => _ProduccionScreenState();
}

class _ProduccionScreenState extends State<ProduccionScreen> {
  Stream<Filas> _sProd = flujo('productos');
  Stream<Filas> _sIns = flujo('insumos');
  late Future<Filas> _recetas = _cargarRecetas();

  Future<Filas> _cargarRecetas() =>
      db.from('producto_insumos').select('producto_id, insumo_id, cantidad');

  void _recargarRecetas() {
    if (mounted) setState(() => _recetas = _cargarRecetas());
  }

  Future<void> editar(BuildContext c, [Map<String, dynamic>? p]) async {
    final f = await formulario(
        c,
        p == null ? 'Nuevo producto' : 'Editar producto',
        {
          'nombre': 'Nombre',
          'unidad': 'Unidad (pza, kg...)',
          'codigo': 'ID del producto (ej. MIEL1K)',
          'gramaje': 'Gramaje (ej. 500)',
          'gramaje_unidad': 'Unidad del gramaje (g o kg)',
          'vida_util_meses': 'Vida útil en meses (consumo recomendado)',
        },
        datos: p == null
            ? {'unidad': 'pza', 'gramaje_unidad': 'g'}
            : {...p, 'gramaje': p['gramaje'] == null ? '' : fmt(p['gramaje'])},
        numericos: {'vida_util_meses', 'gramaje'},
        requeridos: {'nombre'});
    if (f == null || f['nombre']!.isEmpty) return;

    final gTexto = f['gramaje']!;
    final gramaje = gTexto.isEmpty ? null : parseNum(gTexto);
    var gUnidad = f['gramaje_unidad']!.toLowerCase();
    if (gUnidad.isEmpty || gUnidad == 'gr') gUnidad = 'g';
    if ((gTexto.isNotEmpty && (gramaje == null || gramaje <= 0)) ||
        !{'g', 'kg'}.contains(gUnidad)) {
      if (c.mounted) aviso(c, 'Gramaje inválido: usa un número y g o kg');
      return;
    }
    final vTxt = f['vida_util_meses']!;
    int? vida;
    if (vTxt.isNotEmpty) {
      vida = int.tryParse(vTxt);
      if (vida == null || vida <= 0) {
        if (c.mounted) {
          aviso(c, 'Vida útil inválida: usa meses enteros mayores a 0');
        }
        return;
      }
    }
    final d = <String, dynamic>{
      'nombre': f['nombre'],
      'unidad': f['unidad']!.isEmpty ? 'pza' : f['unidad'],
      'codigo': f['codigo']!.isEmpty ? null : f['codigo']!.toUpperCase(),
      'gramaje': gramaje,
      'gramaje_unidad': gUnidad,
      'vida_util_meses': vida,
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

  // Pide de qué entrada sale la miel. null = cancelado.
  Future<String?> elegirEntrada(BuildContext c, Filas entradas) =>
      showDialog<String>(
        context: c,
        builder: (ctx) => SimpleDialog(
          title: const Text('¿De qué entrada sale la miel?'),
          children: [
            for (final e in entradas)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e['id'] as String),
                child: Text(textoEntrada(e)),
              ),
          ],
        ),
      );

  Future<void> darSalida(BuildContext c, Map<String, dynamic> p) async {
    String? entradaId;
    try {
      final Filas receta = await db
          .from('producto_insumos')
          .select('insumo_id, insumos(es_miel)')
          .eq('producto_id', p['id']);
      final mieles = receta
          .where((r) => r['insumos']?['es_miel'] == true)
          .map((r) => r['insumo_id'])
          .toSet();
      if (mieles.length > 1) {
        if (c.mounted) {
          aviso(c, 'La receta tiene más de una miel. Deja solo una');
        }
        return;
      }
      if (mieles.isNotEmpty) {
        if (p['gramaje'] == null) {
          if (c.mounted) aviso(c, 'Primero define el gramaje del producto');
          return;
        }
        final entradas = (await entradasDisponibles())
            .where((e) => mieles.contains(e['insumo_id']))
            .toList();
        if (!c.mounted) return;
        if (entradas.isEmpty) {
          aviso(c, 'No hay entradas con saldo. Regístrala en Trazabilidad');
          return;
        }
        entradaId = await elegirEntrada(c, entradas);
        if (entradaId == null) return;
      }
    } catch (e) {
      if (c.mounted) aviso(c, msgError(e));
      return;
    }
    if (!c.mounted) return;
    final f = await formulario(
        c,
        'Salida de ${p['nombre']}',
        {
          'cantidad': 'Cantidad de piezas',
          'flora': 'Tipo de miel / flora (opcional)',
          'apiario': 'Apiario de origen (opcional)',
          'nota': 'Nota (opcional)',
        },
        numericos: {'cantidad'},
        requeridos: {'cantidad'});
    if (f == null) return;
    final cant = parseNum(f['cantidad'] ?? '');
    if (cant == null || cant <= 0) {
      if (c.mounted) aviso(c, 'La cantidad debe ser un número mayor que cero');
      return;
    }
    try {
      final r = await db.rpc('registrar_salida_trazable', params: {
        'p_producto': p['id'],
        'p_cantidad': cant,
        'p_nota': vacioNull(f['nota']),
        'p_flora': vacioNull(f['flora']),
        'p_apiario': vacioNull(f['apiario']),
        'p_entrada': entradaId,
      });
      final l = r is List ? r.first : r;
      if (!c.mounted) return;
      await showDialog(
        context: c,
        builder: (ctx) => AlertDialog(
          title: const Text('Salida registrada'),
          content: SelectableText(
              'Clave: ${l['clave'] ?? l['codigo']}\nConsumo recomendado: ${l['fecha_consumo_recomendado'] ?? 'sin definir'}\n\nSe descontaron los insumos de la receta.'),
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
  int? alcanza(Map<String, dynamic> p, Filas recetas,
      Map<String, Map<String, dynamic>> ins) {
    final r = recetas.where((x) => x['producto_id'] == p['id']).toList();
    if (r.isEmpty) return null;
    int? m;
    for (final x in r) {
      final insumo = ins[x['insumo_id']];
      final por = porPieza(p, insumo, (x['cantidad'] as num));
      if (por == null || por <= 0) continue;
      final e = ((insumo?['existencia'] ?? 0) as num).toDouble();
      final n = ((e / por) + 1e-9).floor();
      if (m == null || n < m) m = n;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    void reintentar() => setState(() {
          _sProd = flujo('productos');
          _sIns = flujo('insumos');
        });
    return StreamBuilder<Filas>(
      stream: _sProd,
      builder: (ctx, sp) => StreamBuilder<Filas>(
        stream: _sIns,
        builder: (ctx, si) {
          final e1 = pendiente(sp, reintentar) ?? pendiente(si, reintentar);
          if (e1 != null) return e1;
          final ins = <String, Map<String, dynamic>>{
            for (final x in si.data!) x['id'] as String: x
          };
          return FutureBuilder<Filas>(
            future: _recetas,
            builder: (ctx, sr) {
              final e2 = pendiente(sr, _recargarRecetas);
              if (e2 != null) return e2;
              final recetas = sr.data!;
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
                      child: titulo('Productos · Producción y Envasado')),
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
  }

  Widget tarjeta(BuildContext c, Map<String, dynamic> p, Filas recetas,
      Map<String, Map<String, dynamic>> ins) {
    final a = alcanza(p, recetas, ins);
    final rec = recetas.where((x) => x['producto_id'] == p['id']);
    final faltaGramaje =
        p['gramaje'] == null && rec.any((x) => ins[x['insumo_id']]?['es_miel'] == true);
    final String estado;
    if (faltaGramaje) {
      estado = 'Define el gramaje del producto (menú ⋮ > Editar)';
    } else if (a == null) {
      estado = 'Sin receta (toca para agregar insumos)';
    } else {
      estado = 'Con el stock actual alcanza para $a ${p['unidad']}';
    }
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
              c, MaterialPageRoute(builder: (_) => RecetaScreen(producto: p)));
          _recargarRecetas();
        },
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
            if (p['codigo'] != null || p['gramaje'] != null)
              Text(
                  '${p['codigo'] != null ? 'ID ${p['codigo']}' : ''}'
                  '${p['codigo'] != null && p['gramaje'] != null ? ' · ' : ''}'
                  '${p['gramaje'] != null ? '${fmt(p['gramaje'])} ${p['gramaje_unidad']}' : ''}',
                  style: const TextStyle(color: Colors.black54)),
            Text(estado,
                style: TextStyle(
                    color: faltaGramaje || a == null || a == 0
                        ? Colors.red
                        : null,
                    fontSize: 16)),
            Text('Existencia: ${fmt(p['existencia'])} ${p['unidad']}'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  style: grande,
                  onPressed: () => darSalida(c, p),
                  icon: const Icon(Icons.output),
                  label: const Text('Dar salida (genera clave)')),
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
      .select('insumo_id, cantidad, insumos(nombre, unidad, es_miel)')
      .eq('producto_id', widget.producto['id']);

  Future<void> asignar() async {
    final Filas insumos;
    try {
      insumos = await db
          .from('insumos')
          .select('id, nombre, unidad, es_miel')
          .order('nombre');
    } catch (e) {
      if (mounted) aviso(context, msgError(e));
      return;
    }
    if (!mounted) return;
    String? sel;
    final cant = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final ins = insumos.where((i) => i['id'] == sel).firstOrNull;
        final esMiel = ins?['es_miel'] == true;
        final auto = esMiel ? porPieza(widget.producto, ins, 0) : null;
        if (esMiel && auto != null && cant.text != fmt(auto)) {
          cant.text = fmt(auto);
        }
        final q = parseNum(cant.text);
        final valido =
            sel != null && (esMiel ? auto != null : (q != null && q > 0));
        return AlertDialog(
          title: const Text('Agregar insumo a la receta'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              hint: const Text('Insumo'),
              isExpanded: true,
              items: [
                for (final i in insumos)
                  DropdownMenuItem<String>(
                      value: i['id'] as String,
                      child: Text('${i['nombre']} (${i['unidad']})'))
              ],
              onChanged: (v) => set(() {
                sel = v;
                cant.text = '';
              }),
            ),
            TextField(
                controller: cant,
                readOnly: esMiel,
                onChanged: (_) => set(() {}),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cantidad por cada pieza',
                  helperText:
                      esMiel && auto != null ? 'Se calcula del gramaje del producto' : null,
                  errorText: esMiel && auto == null
                      ? 'Define el gramaje del producto y usa unidad kg o g en la miel'
                      : null,
                )),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: valido ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Guardar')),
          ],
        );
      }),
    );
    final insFinal = insumos.where((i) => i['id'] == sel).firstOrNull;
    final double? valor = insFinal?['es_miel'] == true
        ? porPieza(widget.producto, insFinal, 0)
        : parseNum(cant.text)?.toDouble();
    liberar([cant]);
    if (ok == true && sel != null && valor != null && valor > 0) {
      try {
        await db.from('producto_insumos').upsert({
          'producto_id': widget.producto['id'],
          'insumo_id': sel,
          'cantidad': valor
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
            final espera = pendiente(snap, () => setState(() {}));
            if (espera != null) return espera;
            if (snap.data!.isEmpty) {
              return const Center(child: Text('Sin insumos asignados'));
            }
            return ListView(children: [
              for (final r in snap.data!)
                ListTile(
                  title: Text(r['insumos']['nombre']),
                  subtitle: Text(
                      '${fmt(porPieza(widget.producto, r['insumos'], r['cantidad'] as num) ?? r['cantidad'])} ${r['insumos']['unidad']} por pieza'),
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

// ================= 4. TRAZABILIDAD (entradas y salidas) =================
// Entradas: movimientos de insumos con cantidad > 0 (la miel exige productor).
// Salidas: movimientos de insumos con cantidad < 0 (manuales) + lotes de
// producto (salidas generadas desde la pestaña Producto).
// Requiere haber ejecutado sql.sql (vista entradas_miel, triggers y RPC).
enum TipoFlujo { entradas, salidas }

const _selLote = '*, productos(nombre, unidad), '
    'entrada:movimientos!lotes_entrada_id_fkey('
    'upp_origen, proveedores(nombre, upp_id))';
const _selMovimiento = 'id, created_at, cantidad, nota, clave, upp_origen, '
    'insumos(nombre, unidad), proveedores(nombre, upp_id, rasmiel)';

/// Entradas de miel que aún tienen saldo, de la más antigua a la más nueva.
Future<Filas> entradasDisponibles() => db
    .from('entradas_miel')
    .select()
    .gt('disponible', 0)
    .order('created_at', ascending: true);

String textoEntrada(Map<String, dynamic> e) =>
    '${e['clave'] ?? 'Sin clave'} · ${e['productor'] ?? 'Sin productor'} · '
    '${fmt(e['disponible'])} ${e['unidad']}';

String fechaHora(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '-';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
}

class TrazabilidadScreen extends StatefulWidget {
  const TrazabilidadScreen({super.key});
  @override
  State<TrazabilidadScreen> createState() => _TrazabilidadScreenState();
}

class _TrazabilidadScreenState extends State<TrazabilidadScreen> {
  TipoFlujo modo = TipoFlujo.entradas;
  late Future<Filas> f = cargar();
  String busqueda = '';
  int limite = 300; // PostgREST corta en 1000 filas: se pagina de 300 en 300
  bool hayMas = false;

  bool get esEntrada => modo == TipoFlujo.entradas;

  Future<Filas> cargar() async {
    if (modo == TipoFlujo.entradas) {
      final r = await db
          .from('movimientos')
          .select(_selMovimiento)
          .not('insumo_id', 'is', null)
          .gt('cantidad', 0)
          .order('created_at', ascending: false)
          .limit(limite);
      hayMas = r.length >= limite;
      return r;
    }
    final r = await Future.wait<Filas>([
      // Salidas manuales de insumos (las de receta se ven dentro de cada lote)
      db
          .from('movimientos')
          .select(_selMovimiento)
          .not('insumo_id', 'is', null)
          .lt('cantidad', 0)
          .isFilter('lote_id', null)
          .order('created_at', ascending: false)
          .limit(limite),
      db
          .from('lotes')
          .select(_selLote)
          .order('created_at', ascending: false)
          .limit(limite),
    ]);
    hayMas = r[0].length >= limite || r[1].length >= limite;
    final todos = <Map<String, dynamic>>[
      for (final m in r[0]) {...m, '_tipo': 'mov'},
      for (final l in r[1]) {...l, '_tipo': 'lote'},
    ];
    todos.sort(
        (a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    return todos;
  }

  void recargar() => setState(() => f = cargar());

  void cambiarModo(TipoFlujo m) {
    if (m == modo) return;
    setState(() {
      modo = m;
      limite = 300;
      f = cargar();
    });
  }

  bool coincide(Map<String, dynamic> r) {
    if (busqueda.isEmpty) return true;
    final textos = r['_tipo'] == 'lote'
        ? [
            '${r['clave'] ?? ''}',
            '${r['codigo']}',
            '${r['productos']?['nombre'] ?? ''}',
            '${r['entrada']?['proveedores']?['nombre'] ?? ''}',
            '${r['entrada']?['proveedores']?['upp_id'] ?? ''}',
          ]
        : [
            '${r['clave'] ?? ''}',
            '${r['insumos']?['nombre'] ?? ''}',
            '${r['proveedores']?['nombre'] ?? ''}',
            '${r['proveedores']?['upp_id'] ?? ''}',
            '${r['proveedores']?['rasmiel'] ?? ''}',
            '${r['nota'] ?? ''}',
          ];
    return textos.any((t) => t.toLowerCase().contains(busqueda));
  }

  // Registra una entrada o salida tomando insumos y proveedores ya dados de alta.
  Future<void> registrar() async {
    final entrada = esEntrada;
    final Filas insumos;
    final Filas provs, entradas;
    try {
      final r = await Future.wait<Filas>([
        db
            .from('insumos')
            .select('id, nombre, unidad, existencia, es_miel')
            .order('nombre'),
        db
            .from('proveedores')
            .select('id, nombre, upp_id, upp_otro, upp_otro_nombre')
            .order('nombre'),
        entradasDisponibles(),
      ]);
      insumos = r[0];
      provs = r[1];
      entradas = r[2];
    } catch (e) {
      if (mounted) aviso(context, msgError(e));
      return;
    }
    if (!mounted) return;
    if (insumos.isEmpty) {
      aviso(context, 'Primero registra insumos en la pestaña Insumos');
      return;
    }
    String? insSel, provSel, uppSel, entSel;
    final cant = TextEditingController(), nota = TextEditingController();
    double? cantidad() => double.tryParse(cant.text.trim().replaceAll(',', '.'));
    Map<String, dynamic>? insumo() =>
        insumos.where((i) => i['id'] == insSel).firstOrNull;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (_, set) {
        final q = cantidad();
        final i = insumo();
        final miel = i?['es_miel'] == true;
        final prov = provs.where((p) => p['id'] == provSel).firstOrNull;
        final origenes =
            entradas.where((e) => e['insumo_id'] == insSel).toList();
        final ent = origenes.where((e) => e['id'] == entSel).firstOrNull;
        final excede =
            ent != null && q != null && q > (ent['disponible'] as num);
        final excedeExist = !entrada &&
            !miel &&
            i != null &&
            q != null &&
            q > (i['existencia'] as num);
        final valido = insSel != null &&
            q != null &&
            q > 0 &&
            (!miel || (entrada ? provSel != null : ent != null)) &&
            !excede &&
            !excedeExist;
        return AlertDialog(
          title: Text(entrada ? 'Registrar entrada' : 'Registrar salida'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: insSel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Insumo'),
                items: [
                  for (final x in insumos)
                    DropdownMenuItem<String>(
                      value: x['id'] as String,
                      child: Text(
                          '${x['nombre']} · ${fmt(x['existencia'])} ${x['unidad']}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => set(() {
                  insSel = v;
                  entSel = null;
                  uppSel = null;
                }),
              ),
              if (entrada)
                DropdownButtonFormField<String?>(
                  initialValue: provSel,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: miel
                          ? 'Productor (ID / UPP)'
                          : 'Proveedor (opcional)',
                      helperText: miel && provs.isEmpty
                          ? 'Primero registra un productor en Proveedores'
                          : null),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin proveedor')),
                    for (final p in provs)
                      DropdownMenuItem<String?>(
                        value: p['id'] as String,
                        child: Text('${p['nombre']} · UPP ${p['upp_id']}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => set(() {
                    provSel = v;
                    uppSel = null;
                  }),
                ),
              if (entrada && miel && prov?['upp_otro'] != null)
                DropdownButtonFormField<String?>(
                  key: ValueKey(provSel),
                  initialValue: uppSel,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Origen de la miel'),
                  items: [
                    DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Granja propia · ${prov!['upp_id']}',
                            overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem<String?>(
                        value: prov['upp_otro'] as String,
                        child: Text(
                            'UPP de otro · ${prov['upp_otro']} ${prov['upp_otro_nombre'] ?? ''}',
                            overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => uppSel = v),
                ),
              if (!entrada && miel)
                DropdownButtonFormField<String>(
                  key: ValueKey(insSel),
                  initialValue: entSel,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: 'Entrada de miel de origen',
                      helperText: origenes.isEmpty
                          ? 'No hay entradas con saldo de esta miel'
                          : null),
                  items: [
                    for (final e in origenes)
                      DropdownMenuItem<String>(
                        value: e['id'] as String,
                        child: Text(textoEntrada(e),
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => set(() => entSel = v),
                ),
              TextField(
                controller: cant,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                    labelText: 'Cantidad',
                    errorText: excede
                        ? 'Supera el saldo de esa entrada'
                        : (excedeExist ? 'Supera la existencia' : null),
                    suffixText: i == null ? null : '${i['unidad']}',
                    helperText: !entrada && i != null
                        ? 'Existencia: ${fmt(i['existencia'])} ${i['unidad']}'
                        : null),
                onChanged: (_) => set(() {}),
              ),
              TextField(
                controller: nota,
                decoration: InputDecoration(
                    labelText: entrada
                        ? 'Nota (factura, remisión...)'
                        : 'Nota (destino, motivo...)'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ambar),
                onPressed: valido ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Guardar')),
          ],
        );
      }),
    );
    final q = cantidad();
    final n = nota.text.trim();
    liberar([cant, nota]);
    if (ok != true || insSel == null || q == null || q <= 0) return;
    final esMielFinal = insumo()?['es_miel'] == true;

    try {
      final r = await db
          .from('movimientos')
          .insert({
            'insumo_id': insSel,
            'proveedor_id': entrada ? provSel : null,
            'upp_origen': entrada && esMielFinal ? uppSel : null,
            'entrada_id': entrada ? null : entSel,
            'cantidad': entrada ? q : -q,
            'nota': n.isEmpty ? null : n,
          })
          .select('clave')
          .single();
      if (!mounted) return;
      final hecho = entrada ? 'Entrada registrada' : 'Salida registrada';
      aviso(context,
          r['clave'] == null ? hecho : '$hecho · Clave ${r['clave']}');
      recargar();
    } catch (e) {
      if (mounted) aviso(context, msgError(e));
    }
  }

  void detalle(Map<String, dynamic> l) => showModalBottomSheet(
        context: context,
        builder: (_) => FutureBuilder<Filas>(
          future: db
              .from('movimientos')
              .select('cantidad, insumos(nombre, unidad)')
              .eq('lote_id', l['id']),
          builder: (ctx, s) {
            if (s.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No se pudo cargar.\n${msgError(s.error!)}'),
              );
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('${l['clave'] ?? l['codigo']}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: ambar)),
              const SizedBox(height: 4),
              const Text('Insumos consumidos:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (!s.hasData) const LinearProgressIndicator(),
              if (s.hasData && s.data!.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Este lote no consumió insumos.')),
              for (final m in s.data ?? <Map<String, dynamic>>[])
                ListTile(
                  dense: true,
                  title: Text('${m['insumos']?['nombre'] ?? 'Insumo eliminado'}'),
                  trailing: Text(
                      '${fmt((m['cantidad'] as num).abs())} ${m['insumos']?['unidad'] ?? ''}'),
                ),
            ]);
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: ambar,
          onPressed: registrar,
          icon: Icon(esEntrada ? Icons.login : Icons.logout,
              color: Colors.white),
          label: Text(esEntrada ? 'Entrada' : 'Salida',
              style: const TextStyle(color: Colors.white)),
        ),
        body: Column(children: [
          Align(
              alignment: Alignment.centerLeft,
              child: titulo('Trazabilidad · Entradas y Salidas')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<TipoFlujo>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: ambar,
                  selectedForegroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                segments: const [
                  ButtonSegment(
                      value: TipoFlujo.entradas,
                      icon: Icon(Icons.login),
                      label: Text('Entradas')),
                  ButtonSegment(
                      value: TipoFlujo.salidas,
                      icon: Icon(Icons.logout),
                      label: Text('Salidas')),
                ],
                selected: {modo},
                onSelectionChanged: (s) => cambiarModo(s.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) =>
                  setState(() => busqueda = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: esEntrada
                    ? 'Buscar clave, insumo, productor o UPP...'
                    : 'Buscar clave, producto, insumo o productor...',
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
                recargar();
                try {
                  await f;
                } catch (_) {}
              },
              child: FutureBuilder<Filas>(
                future: f,
                builder: (ctx, s) {
                  if (s.hasError) {
                    return ListView(children: [
                      const SizedBox(height: 120),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            'No se pudieron cargar los registros.\n${msgError(s.error!)}',
                            textAlign: TextAlign.center),
                      ),
                    ]);
                  }
                  if (!s.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final filas = s.data!.where(coincide).toList();
                  if (filas.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                          child: Text(esEntrada
                              ? 'Sin entradas. Pulsa "Entrada" para registrar una.'
                              : 'Sin salidas. Registra una o da salida a un producto.')),
                    ]);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: filas.length + (hayMas ? 1 : 0),
                    itemBuilder: (_, k) {
                      if (k == filas.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: TextButton(
                            onPressed: () => setState(() {
                              limite += 300;
                              f = cargar();
                            }),
                            child: const Text('Cargar más registros'),
                          ),
                        );
                      }
                      return filas[k]['_tipo'] == 'lote'
                          ? loteCard(filas[k])
                          : movimientoCard(filas[k]);
                    },
                  );
                },
              ),
            ),
          ),
        ]),
      );

  Widget movimientoCard(Map<String, dynamic> m) {
    final ins = m['insumos'] as Map<String, dynamic>?;
    final prov = m['proveedores'] as Map<String, dynamic>?;
    final entrada = (m['cantidad'] as num) > 0;
    final color = entrada ? const Color(0xFF15803D) : const Color(0xFFB45309);
    final nota = (m['nota'] ?? '') as String;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(entrada ? Icons.login : Icons.logout, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${ins?['nombre'] ?? 'Insumo eliminado'}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: cafe))),
            Chip(
              label: Text(
                  '${entrada ? '+' : '-'}${fmt((m['cantidad'] as num).abs())} ${ins?['unidad'] ?? ''}',
                  style: const TextStyle(color: Colors.white)),
              backgroundColor: color,
            ),
          ]),
          Text(fechaHora(m['created_at']),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (m['clave'] != null)
            SelectableText('${m['clave']}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: ambar)),
          const SizedBox(height: 8),
          if (prov != null)
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
                    Text(
                        entrada
                            ? 'Proveedor: ${prov['nombre']}'
                            : 'Origen: ${prov['nombre']}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('UPP ${prov['upp_id']}  ·  RASMIEL ${prov['rasmiel']}',
                        style: const TextStyle(
                            fontSize: 13, letterSpacing: 0.5, color: cafe)),
                    if (m['upp_origen'] != null &&
                        m['upp_origen'] != prov['upp_id'])
                      Text('UPP de otro: ${m['upp_origen']}'),
                  ]),
            )
          else
            Text(entrada ? 'Sin proveedor' : 'Sin proveedor de origen',
                style: const TextStyle(color: Colors.black45)),
          if (nota.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Nota: $nota'),
          ],
        ]),
      ),
    );
  }

  Widget loteCard(Map<String, dynamic> l) {
    final p = l['productos'];
    final origen = l['entrada'] as Map<String, dynamic>?;
    final productor = origen?['proveedores'] as Map<String, dynamic>?;
    final uppOrigen = origen?['upp_origen'];
    final extra = <String>[
      if (productor != null)
        'Productor: ${productor['nombre']} · ID/UPP ${productor['upp_id']}',
      // Antes mostraba "UPP de otro: null" cuando la miel era de granja propia
      if (productor != null &&
          uppOrigen != null &&
          uppOrigen != productor['upp_id'])
        'UPP de otro: $uppOrigen',
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
                  child: Text('${l['clave'] ?? l['codigo']}',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: ambar))),
              Chip(
                label: Text('${fmt(l['cantidad'])} ${p?['unidad'] ?? ''}',
                    style: const TextStyle(color: Colors.white)),
                backgroundColor: const Color(0xFFB45309),
              ),
            ]),
            const Text('Salida de producto',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const Divider(),
            Text('Producto: ${p?['nombre'] ?? '-'}'),
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

// ---------------- UTILIDADES ----------------
Future<void> mover(
    BuildContext c, String tabla, Map<String, dynamic> it, double signo) async {
  if (tabla == 'insumos' && it['es_miel'] == true) {
    // Sin productor ni entrada de origen se perdería la trazabilidad
    aviso(c, 'La miel se registra en Trazabilidad para conservar su clave');
    return;
  }
  final tipo = signo > 0 ? 'Entrada' : 'Salida';
  final cant = await pedirNumero(c, '$tipo · ${it['nombre']}');
  if (cant == null) return;
  final hay = ((it['existencia'] ?? 0) as num);
  if (signo < 0 && cant > hay) {
    if (c.mounted) {
      aviso(c,
          'Existencia insuficiente (hay ${fmt(hay)} ${it['unidad']})');
    }
    return;
  }
  try {
    await db.from('movimientos').insert({
      (tabla == 'productos' ? 'producto_id' : 'insumo_id'): it['id'],
      'cantidad': cant * signo,
    });
    if (c.mounted) aviso(c, 'Movimiento registrado');
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
// "requeridos" = campos que no pueden quedar vacíos (el botón Guardar se
// habilita solo cuando están llenos; antes el diálogo se cerraba y se perdía todo).
Future<Map<String, String>?> formulario(
    BuildContext c, String titulo, Map<String, String> campos,
    {Map<String, dynamic>? datos,
    bool eliminar = false,
    Set<String> numericos = const {},
    Set<String> requeridos = const {}}) {
  return showDialog<Map<String, String>>(
    context: c,
    builder: (_) => _FormDialog(
      titulo: titulo,
      campos: campos,
      datos: datos,
      eliminar: eliminar,
      numericos: numericos,
      requeridos: requeridos,
    ),
  );
}

class _FormDialog extends StatefulWidget {
  final String titulo;
  final Map<String, String> campos;
  final Map<String, dynamic>? datos;
  final bool eliminar;
  final Set<String> numericos;
  final Set<String> requeridos;
  const _FormDialog({
    required this.titulo,
    required this.campos,
    required this.datos,
    required this.eliminar,
    required this.numericos,
    required this.requeridos,
  });
  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  late final Map<String, TextEditingController> ctrl = {
    for (final k in widget.campos.keys)
      k: TextEditingController(text: '${widget.datos?[k] ?? ''}')
  };

  @override
  void dispose() {
    for (final x in ctrl.values) {
      x.dispose();
    }
    super.dispose();
  }

  bool get valido => widget.requeridos
      .every((k) => (ctrl[k]?.text.trim() ?? '').isNotEmpty);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.titulo),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in widget.campos.entries)
              TextField(
                controller: ctrl[e.key],
                keyboardType: widget.numericos.contains(e.key)
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: e.value),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          if (widget.eliminar)
            TextButton(
                onPressed: () => Navigator.pop(context, {'__eliminar': '1'}),
                child: const Text('Eliminar')),
          FilledButton(
              onPressed: valido
                  ? () => Navigator.pop(context,
                      {for (final k in ctrl.keys) k: ctrl[k]!.text.trim()})
                  : null,
              child: const Text('Guardar')),
        ],
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
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aceptar')),
      ],
    ),
  );
  final v = parseNum(t.text)?.toDouble();
  liberar([t]);
  if (ok == true && (v == null || v <= 0)) {
    if (c.mounted) aviso(c, 'Escribe una cantidad mayor que cero');
    return null;
  }
  return (ok == true) ? v : null;
}

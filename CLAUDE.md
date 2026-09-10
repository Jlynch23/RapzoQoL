# Rapzo QoL — Contexto completo para Claude

> Lee este archivo completo antes de modificar el addon. Lee tambien `AGENTS.md` y
> `CODEX_HANDOFF.md`, pero usa siempre el codigo actual como fuente final de verdad.

## 1. Identidad y estado del repositorio

- Repositorio actual: `https://github.com/Jlynch23/RapzoQoL`
- Nombre anterior del repositorio: `Jlynch23/RapzoBags` (GitHub redirige al nombre nuevo).
- Rama unica de trabajo: `main`
- Fecha del snapshot: 2026-09-03
- Version declarada por el addon: `3.0.0-alpha5`
- Ultimo tag publicado visible: `v3.0.0-alpha3`
- WoW Retail Interface: `120100` (Retail 12.1.0)

Flujo de trabajo con una sola rama:

1. Al empezar cualquier sesion, leer este CLAUDE.md completo para saber donde quedamos.
2. Desarrollar y commitear directamente en `main`; no crear ramas nuevas salvo peticion
   explicita de Rapzo.
3. Al terminar, actualizar este CLAUDE.md: sumar lo nuevo, borrar lo obsoleto y dejar solo lo
   util. Despues subir todo a `main`.

Regla por repositorio (no mezclar): la rama unica `main` es SOLO de Rapzo QoL, que es el
proyecto para jugar. El repositorio del negocio, `Jlynch23/textil-inventario` (TexControl,
ventas, desarrollo serio), trabaja con DOS ramas: `dev` y `main` — alli todo se sube a `dev`
para probar, y `main` no se toca sin decision de Rapzo.

Los documentos historicos (`AGENTS.md`, `CODEX_HANDOFF.md`) pueden estar atrasados; el codigo
actual y este archivo mandan.

Comandos de comprobacion obligatorios antes de trabajar:

```bash
git status --short --branch
git branch --show-current
git log -5 --oneline
```

La rama esperada es:

```text
main
```

## 2. Objetivo del proyecto

Rapzo QoL es una suite modular de calidad de vida para World of Warcraft Retail. Reune en un
solo addon:

- inventario por personaje y cuenta;
- tooltip enriquecido;
- buscador global de objetos y oro;
- deteccion de coleccionables;
- vendedor extendido con filtros;
- filtro automatico de expansion actual en AH y pedidos de fabricacion;
- pantalla AFK;
- HUD visual con aro del cursor, minimapa cuadrado y Unit Frames;
- panel de configuracion propio y panel en las opciones de Blizzard.

World of Warcraft debe ver una sola carpeta:

```text
Interface/AddOns/RapzoQoL/
```

No vuelvas a separar el proyecto en `RapzoBags_Core`, `RapzoBags_HUD`, etc. Esos nombres solo
pertenecen a la historia del proyecto.

## 3. Forma de trabajar con el propietario

El propietario es Rapzo. Cuando pida una correccion o funcion:

1. Haz el cambio directamente en el repositorio si tienes acceso de escritura.
2. No le pidas que copie y pegue Lua, TOC o HTML si puedes editarlo tu.
3. Trabaja directamente en `main`; el repositorio usa una sola rama.
4. Conserva lo que funciona; no hagas refactors masivos sin necesidad.
5. Revisa diff, rama, commit final y estado de Git antes de declarar que terminaste.
6. Rapzo normalmente solo debe hacer `git pull`, `/reload` y probar dentro de WoW.
7. No pidas una segunda confirmacion cuando la instruccion ya es clara.
8. No crees tags ni publiques releases sin una peticion explicita.

Para cambios visuales del HUD, conserva siempre que sea posible dos vias de prueba:

- preview offline en `preview/index.html`;
- preview dentro de WoW mediante `/rapzo hud preview`.

## 4. Stack y limites tecnicos

- Lua compatible con el entorno embebido de WoW Retail.
- APIs de Blizzard/FrameXML, incluyendo APIs de Retail 12.x y valores secretos.
- Sin Ace3, LibStub ni dependencias externas.
- Sin proceso de compilacion.
- No existe una suite automatizada capaz de probar comportamiento real de frames protegidos.
- La validacion final de HUD, auras, castbars, MerchantFrame y combate ocurre dentro de WoW.

El codigo usa `pcall`, comprobacion de capacidades y `RB:RegisterEventSafe()` porque Blizzard
cambia APIs entre parches. Mantener este estilo defensivo. No inspeccionar, comparar, convertir a
texto ni hacer operaciones aritmeticas sobre un valor si `issecretvalue(value)` devuelve `true`.

## 5. Arquitectura actual: un solo addon

El TOC real es `RapzoQoL/RapzoQoL.toc` y carga los archivos en este orden:

```text
Core/Core.lua
Core/Scanner.lua

Modules/Tooltip/Tooltip.lua
Modules/Search/Search.lua
Modules/Collections/Collections.lua
Modules/Vendor/Vendor.lua
Modules/QoL/ExpansionFilters.lua
Modules/AFK/AFK.lua
Modules/AFK/AFKBrand.lua
Modules/ReflectHerald/ReflectHerald.lua

Modules/HUD/HUD.lua
Modules/HUD/HUDFixes.lua
Modules/HUD/HUDStyles.lua
Modules/HUD/ClassResources.lua
Modules/HUD/AuraAnchors.lua
Modules/HUD/HUDPreview.lua

Config/Config.lua
```

El orden importa. Los archivos que amplian `RB.HUD` necesitan que `HUD.lua` ya haya creado el
modulo. Si agregas otro archivo, incluyelo en el TOC en una posicion coherente con sus dependencias.

Media/branding actual:

```text
RapzoQoL/Media/RapzoQoL-Icon.png
```

El icono y la identidad elegida son el escudo Rapzo dorado/azul. El TOC apunta al PNG con:

```text
## IconTexture: Interface\AddOns\RapzoQoL\Media\RapzoQoL-Icon.png
```

## 6. Namespace y contrato entre modulos

El namespace canonico es:

```lua
_G.RapzoQoL
```

Se conserva el alias historico:

```lua
_G.RapzoBags = _G.RapzoQoL
```

Los modulos reciben el namespace global y se registran con `RB:RegisterModule(key, module)`.
Funciones centrales que usan otros modulos:

- `RB:RegisterModule(key, module)`
- `RB:IsModulePresent(key)`
- `RB:IsFeatureEnabled(key)`
- `RB:SetFeatureEnabled(key, enabled, quiet)`
- `RB:RegisterCommand(name, handler, helpText)`
- `RB:RegisterEventSafe(frame, event)`
- `RB:Print(message)`
- `RB:GetItemAggregate(itemID)`
- `RB:GetKnownItemLink(itemID)`
- `RB:GetAllKnownItemIDs()`
- `RB:GetTotalMoney()`
- `RB:GetAccentColor()` / `RB:SetAccentColor()` / `RB:ApplyTheme()`

Los modulos internos registrados actualmente son:

```text
tooltip
search
vendor
collections
expansionFilters
afk
reflectHerald
hud
config
```

`IsModulePresent` significa que el archivo cargo. `IsFeatureEnabled` significa que la funcion esta
activada. No confundas ambos estados.

## 7. SavedVariables y migraciones

La SavedVariable sigue llamandose deliberadamente:

```text
RapzoBagsDB
```

No la renombres a `RapzoQoLDB`: hacerlo perderia el inventario y preferencias existentes.

Estructura base actual (`schema = 5`):

```text
RapzoBagsDB
├── schema
├── characters["Nombre-Reino"]
│   ├── key, name, realm, class, faction, money, lastSeen
│   ├── bags[itemID]      = { count, link }
│   ├── equipped[itemID]  = { count, link }
│   └── bank[itemID]      = { count, link }
├── account
│   └── bank[itemID]      = { count, link }
└── settings
    ├── tooltip, showTotal, showLocations, maxCharacters
    ├── showItemExpansion, showItemType, showItemID
    ├── modules
    ├── theme.accent
    ├── vendor
    ├── afk
    ├── hud
    └── reflectHerald
```

Regla de migracion: completar campos faltantes solo cuando sean `nil`. Nunca reemplazar de golpe
`db.settings`, `db.characters` ni un bloque de configuracion ya existente. Si cambia el formato de
un dato, migrarlo de forma explicita y considerar subir `schema`.

`settings.modules.hud` se mantiene encendido como contenedor interno desde la separacion del HUD.
El estado visual real de los Unit Frames esta en `settings.hud.unitFrames`.

Accent Color por defecto:

```text
RGB 0.22, 0.83, 0.98
```

Se guarda en `settings.theme.accent`. No debe sustituir colores de clase obtenidos de
`RAID_CLASS_COLORS` donde el HUD o AFK requieren color de clase.

## 8. Inventario actual de funciones

### 8.1 Core — `Core/Core.lua`

- Inicializa namespace, DB, modulos y comandos.
- Conserva aliases `/rapzo`, `/rqol`, `/rbags` y `/rapzobags`.
- Registra `/rl` como alias rapido de `/reload`.
- Guarda identidad, clase, faccion, dinero y ultima actividad del personaje.
- Agrega inventario por Item ID para tooltip y busqueda.
- Gestiona Accent Color y lo propaga mediante `ApplyTheme()`.
- Intenta conservar el orden de bolsas:
  - `C_Container.SetSortBagsRightToLeft(false)`
  - `C_Container.SetInsertItemsLeftToRight(false)`

### 8.2 Scanner — `Core/Scanner.lua`

Escanea:

- mochila, bolsas y bolsa de componentes;
- equipo equipado (slots 1..19);
- banco del personaje cuando esta disponible;
- banco de banda de guerra/cuenta cuando la API lo expone;
- Item ID, cantidad y enlace conocido.

Tolera variaciones de `Enum.BagIndex` y usa fallbacks de indices. Tooltip, Search y Vendor dependen
de la informacion agregada por este modulo.

### 8.3 Tooltip — `Modules/Tooltip/Tooltip.lua`

Añade a los tooltips de objetos:

- expansion;
- tipo/subtipo;
- Item ID;
- cantidades conocidas por personaje;
- localizacion (bolsas, equipado, banco);
- banco de banda de guerra;
- total de la cuenta.

Tiene compatibilidad con mUI para no duplicar Item ID y evita apropiarse del tooltip del vendedor
cuando no corresponde.

Defaults importantes:

- tooltip: ON;
- expansion: ON;
- tipo: ON;
- Item ID: ON;
- total: ON;
- localizaciones: ON;
- maximo de personajes mostrados: 12.

### 8.4 Search — `Modules/Search/Search.lua`

- Ventana principal `RapzoQoLSearchFrame` de 760x520.
- Busca por nombre o Item ID en todos los personajes y bancos conocidos.
- Muestra lista, detalle, cantidades y localizaciones.
- Incluye vista de oro por personaje y total.
- `/rapzo` abre Search por defecto si el modulo esta activo.

### 8.5 Collections — `Modules/Collections/Collections.lua`

Resuelve obtenido/no obtenido, segun las APIs disponibles, para:

- mascotas;
- monturas;
- juguetes;
- reliquias;
- apariencias y sets de transfiguracion;
- recetas;
- housing cuando la API/tooltip permite determinarlo.

Usa cache y expone `Collections:ClearCache()`. Vendor consume este estado para filtros y marcas.

### 8.6 Vendor — `Modules/Vendor/Vendor.lua`

Amplia `MerchantFrame` y es uno de los modulos mas delicados.

Funciones:

- grilla configurable, default 4 columnas x 5 filas;
- limites: 2..8 columnas y 5..10 filas;
- filtros: Todos, No obtenidos, Monturas, Transmog y Recetas;
- marca `OBTENIDO` configurable;
- cantidad poseida por Item ID;
- mapeo entre indice visible filtrado e indice real del vendedor;
- restauracion del tamaño y layout nativo al desactivar;
- recolocacion de BuyBack y compatibilidad con sus dos pestañas;
- deteccion de conflicto con `Krowi_ExtendedVendorUI`.

Puntos de riesgo:

- cambia temporalmente `MERCHANT_ITEMS_PER_PAGE`;
- envuelve APIs globales de merchant cuando hay filtro activo;
- usa `hooksecurefunc`, cuyos hooks no se pueden retirar;
- todo hook debe quedar inerte cuando `Vendor.ready`/config no permitan actuar;
- siempre probar Compra, Recompra y el cambio entre ambas pestañas.

Antes de tocar layout revisar juntos:

- `CaptureOriginalLayout`
- `RestoreDefaultMerchantLayout`
- `PositionMerchantBuyBackItem`
- `LayoutMerchantSlots`
- `WrapMerchantAPIs`

### 8.7 Filtro de expansion — `Modules/QoL/ExpansionFilters.lua`

Activa automaticamente `CurrentExpansionOnly` al abrir:

- Auction House / Browse Auctions;
- Customer Orders / Place Crafting Order.

Estado default: ON mediante `settings.modules.expansionFilters`.

La AH se cubre con hook del mixin y del frame real. Pedidos de fabricacion se reaplican despues de
`SetDefaultFilters()`, `Init()` y `OnShow`, porque Blizzard reconstruye filtros al abrir la ventana.
El addon cambia el estado del filtro, pero no lanza automaticamente la busqueda.

Solo tiene control por slash command; actualmente no tiene checkbox propio en Config:

```text
/rapzo expfilter on|off
```

Al apagarlo se detiene la reaplicacion futura; el codigo no fuerza a desmarcar de inmediato un
checkbox ya activo en una ventana abierta.

### 8.8 AFK — `Modules/AFK/AFK.lua` y `AFKBrand.lua`

Pantalla fullscreen con tarjeta central 880x560. Puede mostrar:

- marca Rapzo QoL;
- indicador AFK;
- nombre, nivel, clase y especializacion;
- zona/subzona;
- tiempo AFK;
- reloj;
- dinero opcional;
- footer y texto `Quality of life, the Rapzo way.`

Defaults:

- enabled: ON;
- opacity: 0.84;
- timer: ON;
- personaje: ON;
- zona: ON;
- reloj: ON;
- dinero: OFF;
- ocultar en combate: ON.

La pantalla usa el color de clase actual de Blizzard, con Accent Color como fallback durante
carga. Tiene preview manual. La logica actual evita ramificar sobre valores secretos de
`UnitIsAFK`, reintenta el estado despues y no deja un preview fantasma armado si no pudo mostrarse.
No debe abrir el preview en combate cuando `hideInCombat` esta activo.

### 8.9 Config — `Config/Config.lua`

Hay dos interfaces:

- panel propio completo `RapzoQoLConfigFrame`;
- categoria `ESC > Options > AddOns > Rapzo QoL`.

Controles actuales principales:

- Accent Color;
- Tooltip avanzado;
- expansion, tipo e Item ID;
- Search;
- Collections;
- Vendor;
- AFK;
- Unit Frames Rapzo;
- minimapa cuadrado;
- aro del mouse;
- selector V1 Clasico / V2 ToxiUI;
- preview/depuracion del HUD;
- reescaneo.

Los indicadores de estado de Vendor y HUD fueron corregidos recientemente: Vendor tolera que
`settings.vendor` aun no exista y HUD muestra el switch real de Unit Frames, no el contenedor
`modules.hud` que permanece ON.

### 8.10 ReflectHerald — `Modules/ReflectHerald/ReflectHerald.lua`

Anuncia el hechizo devuelto por Spell Reflection:

- aviso grande en pantalla: RaidWarningFrame SIN codigos de color incrustados (hay clientes que
  no reconocen la cadena con `|cff...|r` dentro del RaidNotice y no muestran nada), con fallback
  a `UIErrorsFrame` si el RaidNotice no esta disponible;
- linea en el chat propio via `RB:Print`;
- aviso corto opcional al grupo/instancia en ingles ("Reflected X - FOR THE ALLIANCE!",
  default ON, `settings.reflectHerald.party`);
- contador de reflejos por sesion.

Detecta `SPELL_MISSED` con `missType == "REFLECT"` sobre el jugador en
`COMBAT_LOG_EVENT_UNFILTERED`. Todo el handler va dentro de `pcall` porque en contenido
restringido de Midnight los valores del combat log pueden ser secretos. El toggle del modulo es
`settings.modules.reflectHerald`. Como el filtro de expansion, por ahora se controla solo por
slash command, sin checkbox propio en Config.

**Hallazgo real de Midnight (2-sep, taint.log de IRONSIDE): el REGISTRO de
`COMBAT_LOG_EVENT_UNFILTERED` es una accion bloqueada para addons.** No lanza error de Lua — el
`pcall` devuelve exito y el juego bloquea la accion con el popup de taint ("blocked from an action
only available to the Blizzard UI"). Leccion general: un `pcall` NO detecta acciones bloqueadas
por taint, solo errores de Lua. El modulo lo maneja asi:

- escucha `ADDON_ACTION_BLOCKED`/`ADDON_ACTION_FORBIDDEN` y se atribuye CUALQUIER bloqueo del
  addon en los ~5 s siguientes a su propio intento — sin filtrar por nombre de funcion, porque
  el evento puede llegar atribuido a `pcall()` (asi encabeza la pila del taint.log) y no a
  `RegisterEvent`;
- al detectarlo persiste `settings.reflectHerald.cleuBlocked = true`, avisa una vez y NO vuelve a
  intentar en logins siguientes (para no repetir el popup);
- `/rapzo reflect retry` limpia el flag y reintenta; por diseño vuelve a provocar el popup una
  vez, y su status se imprime con ~2 s de retardo porque el bloqueo llega como evento asincrono
  despues del intento (un "combat log OK" inmediato seria prematuro);
- solo intenta registrar si el modulo esta habilitado; con el CLEU bloqueado quedan operativos el
  modo test, el toggle de grupo y el status.

Macro de acompanamiento (en WoW, no en el repo): avisa al ACTIVAR Spell Reflection, mientras el
modulo anuncia cuando el reflejo conecta. Solo ASCII — WoW no renderiza emojis en el chat (cajas
vacias) y el guion largo falla segun la fuente; limite de macros: 255 caracteres.

```text
#showtooltip
/cast Spell Reflection
/p Spell Reflection UP - do NOT kick! By Varian's blade, it comes BACK!
```

Plan de desarrollo del modulo, en orden:

1. **Validacion en juego del flujo base** — parcial (2-sep, IRONSIDE): el cliente BLOQUEO el
   registro del combat log (ver hallazgo arriba). Falta validar el modo test, el anuncio de
   grupo, y que `cleuBlocked` deje el popup en una sola aparicion.
2. **Estadisticas persistentes**: acumular reflejos por hechizo en `settings.reflectHerald`
   ademas del contador de sesion, con `/rapzo reflect stats` mostrando sesion e historico.
3. **Anti-spam de grupo**: minimo configurable de segundos entre anuncios al grupo, para
   packs que revientan varios casts seguidos contra el reflejo.
4. **Opciones de anuncio**: canal configurable (party/instance/say/emote), y mensaje epico
   personalizable o aleatorio entre varias frases.
5. **Resumen post-run**: donde Midnight bloquee el CLEU en vivo, explorar un conteo diferido
   al terminar la instancia si alguna API lo permite; si no es viable, documentarlo y cerrar.
6. **Checkbox en Config** cuando el modulo quede estable, junto al resto de toggles.

Cada fase se valida en juego antes de pasar a la siguiente; no adelantar fases sin necesidad.

Nota (2-sep): con el CLEU bloqueado en el cliente actual, las fases 2-4 dependen de que Blizzard
reabra el evento o de encontrar la via alternativa de la fase 5, que sube de prioridad.

## 9. HUD: arquitectura y reglas criticas

El HUD es la zona mas sensible del addon. Antes de cambiarlo, leer juntos los seis archivos:

```text
Modules/HUD/HUD.lua
Modules/HUD/HUDFixes.lua
Modules/HUD/HUDStyles.lua
Modules/HUD/ClassResources.lua
Modules/HUD/AuraAnchors.lua
Modules/HUD/HUDPreview.lua
```

No crees otra familia paralela de hooks, AuraContainers, castbars o eventos sin comprobar primero
si ya existe una implementacion en estos archivos.

### 9.1 Componentes independientes

Los tres componentes visuales se controlan por separado:

- `settings.hud.unitFrames` — Player/Target/Focus de Rapzo;
- `settings.hud.squareMinimap` — minimapa cuadrado sin borde;
- `settings.hud.cursor` — aro del mouse.

Defaults:

```text
unitFrames    ON
squareMinimap ON
cursor        ON
cursorSize    52 px (rango 36..96)
```

Desactivar Unit Frames no debe apagar el aro ni el minimapa. Desactivar el HUD visual antiguo se
migra solo al switch de Unit Frames. `HUD:SetEnabled()` existe por compatibilidad y ahora delega a
`HUD:SetPart("frames", enabled)`.

Al apagar Unit Frames deben restaurarse Player/Target/Focus nativos, sus regiones, arte de descanso,
castbars y contenedores de auras modificados por Rapzo. Los hooks instalados deben quedar inertes.

El minimapa restaura bordes y brujula al apagarlo, pero la mascara cuadrada necesita `/reload` para
volver completamente a la forma nativa.

### 9.2 Unit Frames y colores

Los displays Rapzo son frames propios anclados a los frames Blizzard; no sustituyen la unidad
protegida ni deben escribir campos en barras protegidas.

- Player usa color correcto de clase.
- Target/Focus usan color de clase si la unidad es un jugador.
- Mobs usan los colores fallback del HUD.
- Target/Focus Rapzo se muestran segun `UnitExists`, no segun la visibilidad del frame nativo; esto
  permite convivir con UIs que ocultan visualmente TargetFrame/FocusFrame.
- Los valores secretos de salud/poder pasan directo a `StatusBar`; los textos numericos se vacian
  cuando no se pueden leer con seguridad.

### 9.3 Estilo V1 — Clasico

- Identificador: `style = 1`.
- Tamaño base: 240x64.
- Es la referencia estable que debe conservarse.
- Target/Focus mantienen layout espejado.
- Usa castbars nativas de Blizzard.
- Mantiene el AuraContainer nativo de Target/Focus, reanclado de forma segura cuando corresponde.

Nunca elimines V1 para reemplazarlo con un experimento. Agrega estilos seleccionables o itera V2.

### 9.4 Estilo V2 — ToxiUI

- Identificador: `style = 2`.
- Tamaño base: 150x43.
- Escala default: 1.50x.
- Rango de escala: 0.50x..2.50x.
- Huella base aproximada con default: 225x65 px.
- Diseño compacto, sin portrait dominante, sin panel exterior ni borde de color.
- Nombre arriba, health principal, power fino, auras arriba, castbar abajo.
- Bordes de barras neutrales/negros; el color de clase/reaccion pertenece al health fill.

Auras V2:

- icono base 16 px;
- auraScale default 1.00, rango 0.75..1.75;
- auraOffsetX: -150..150;
- auraOffsetY: -60..100;
- Player: maximo 5 buffs HELPFUL cortos (duracion maxima 120 s);
- Target/Focus: maximo 5 debuffs `HARMFUL|PLAYER`;
- stack y cooldown usan texto compacto;
- V2 oculta la tira mixta nativa de Target/Focus para evitar duplicados.

Castbars V2:

- crea una `RapzoQoLCastBar` por display;
- usa `UnitCastingDuration` / `UnitChannelDuration` cuando estan disponibles;
- V2 oculta castbars nativas guardando y restaurando alpha/mouse;
- V1 y Unit Frames OFF restauran las castbars nativas;
- nunca volver a ocultarlas incondicionalmente;
- validar que haya exactamente una castbar por unidad, no dos ni cuatro.

### 9.5 Recursos secundarios V2

`ClassResources.lua` añade una fila solo al Player y solo cuando corresponde:

- Rogue: Combo Points;
- Feral Druid (spec 103): Combo Points;
- Warlock: Soul Shards, incluido llenado parcial;
- Paladin: Holy Power;
- Windwalker Monk (spec 269): Chi;
- Arcane Mage (spec 62): Arcane Charges;
- Evoker: Essence;
- Death Knight: 6 Runes con recarga.

Geometria base:

```text
ancho 150
alto 6
separacion entre pips 3
```

Clases/specs sin recurso soportado no deben dejar una fila vacia. La castbar del Player se ancla
debajo del recurso cuando la fila es visible y debajo del display cuando no lo es.

### 9.6 Compatibilidad mUI, combate y taint

Problema diagnosticado: con Rapzo QoL y mUI activos aparecia un error como:

```text
FocusFrameSpellBar:SetPoint(): Anchoring disallowed as dependent object would inherit forbidden aspects: UntrustedLayoutScriptExecution
Lua Taint: AddonSuite
.../mUI/.../Auras.lua: AnchorSpellbarToContainer
```

El codigo actual incluye la correccion estructural:

- `AuraAnchors.lua` no modifica contenedores nativos si Unit Frames Rapzo estan OFF;
- solo restaura un contenedor si Rapzo realmente lo habia modificado;
- guarda anchors, ancho y estado visible originales;
- evita `SetPoint`/restauracion durante `InCombatLockdown()` y difiere hasta
  `PLAYER_REGEN_ENABLED`;
- V1 ancla a `UIParent` con coordenadas absolutas para no unir el contenedor protegido a la familia
  de anchors inseguros de Rapzo;
- `HUDFixes.lua` restaura castbars y arte nativo solo si Rapzo los habia cambiado;
- HUDStyles/ClassResources/AuraAnchors quedan inertes cuando Unit Frames estan OFF;
- los displays Target/Focus nativos se restauran al desactivar frames.

No des por cerrado el conflicto solo porque el codigo tiene guards. La prueba definitiva debe
hacerse en WoW con mUI + Rapzo QoL, Target y Focus, V1/V2, Edit Mode y entrada/salida de combate.

### 9.7 Preview HUD

Preview in-game:

```text
/rapzo hud preview
```

`RapzoQoLHUDPreviewFrame` mide 920x680 y ofrece:

- Player, Target y Focus falsos;
- selector V1/V2;
- escala V2;
- escala y posicion de auras;
- escenarios de auras;
- overlay modal seguro;
- cierre antes de abrir desde Blizzard Options.

Preview offline:

```text
preview/index.html
```

Mantener sus dimensiones alineadas con `HUDStyles.lua`. El HTML sirve para geometria y estilo; no
puede validar restricciones de combate, valores secretos, auras reales ni frames protegidos.

## 10. Comandos disponibles

Aliases principales:

```text
/rapzo
/rqol
/rbags
/rapzobags
/rl
```

Core:

```text
/rapzo scan
/rapzo status
/rapzo modules
/rapzo color #RRGGBB
/rapzo color reset
/rapzo help
/rapzo ayuda
/rapzo reset confirm
```

Tooltip:

```text
/rapzo tooltip on|off
/rapzo expansion on|off
/rapzo itemtype on|off
/rapzo tipo on|off
/rapzo itemid on|off
/rapzo id on|off
/rapzo locations on|off
```

Search y oro:

```text
/rapzo search <texto>
/rapzo find <texto>
/rapzo gold
```

Collections:

```text
/rapzo collections on|off|clear
```

Vendor:

```text
/rapzo vendor status
/rapzo vendor on|off
/rapzo vendor 4x5
/rapzo vendor grid 4x5
/rapzo vendor filter all|uncollected|mounts|transmog|recipes
/rapzo vendor obtenidos on|off
/rapzo vendor reset
```

Filtro de expansion:

```text
/rapzo expfilter on|off
```

ReflectHerald (alias corto `/rh`):

```text
/rapzo reflect status
/rapzo reflect on|off
/rapzo reflect party [on|off]
/rapzo reflect test
/rapzo reflect stats
/rapzo reflect retry
```

AFK:

```text
/rapzo afk status
/rapzo afk on|off
/rapzo afk preview
/rapzo afk hide
```

HUD:

```text
/rapzo hud status
/rapzo hud debug
/rapzo hud on|off                 # compatibilidad: controla Unit Frames
/rapzo hud frames on|off
/rapzo hud minimap on|off
/rapzo hud cursor on|off
/rapzo hud cursorsize 36-96
/rapzo hud style 1|2
/rapzo hud scale 0.50-2.50|reset
/rapzo hud aurascale 0.75-1.75|reset
/rapzo hud aurax -150..150|reset
/rapzo hud auray -60..100|reset
/rapzo hud preview [on|off]
```

Config:

```text
/rapzo config
/rapzo options
```

## 11. Avance acumulado hasta este snapshot

Ya esta implementado en codigo:

- renombrado del proyecto a Rapzo QoL;
- migracion de seis addons a una sola carpeta `RapzoQoL`;
- preservacion de `RapzoBagsDB` y aliases antiguos;
- escudo Rapzo e identidad visual;
- Accent Color configurable;
- panel propio y registro en Blizzard Options;
- Tooltip, Search, Collections y Vendor integrados;
- pantalla AFK grande y tematizada por clase;
- filtro de expansion actual para AH y Customer Orders;
- modulo ReflectHerald: anuncio de hechizos devueltos con Spell Reflection;
- `/rl` como reload rapido;
- HUD con partes independientes: frames, minimapa y cursor;
- V1 preservado y V2 ToxiUI seleccionable;
- escala de frames, escala/offset de auras y previews;
- auras y recursos secundarios V2;
- restauracion reversible de frames/castbars/arte Blizzard;
- correcciones de target/focus desaparecidos al apagar Unit Frames;
- correccion para que Target/Focus Rapzo no dependan de que mUI muestre el frame nativo;
- reduccion del aro de cursor y separacion del toggle de HUD;
- guards de combate y restauracion para reducir taint con mUI;
- estados de Config corregidos para HUD y Vendor;
- AFK reforzado frente a combate y valores/eventos secretos;
- nombres internos visibles, mensajes de Vendor, icono y documentacion limpiados.

## 12. Estado pendiente y validacion real

No asumir que "implementado" equivale a "visualmente perfecto". Pendientes actuales:

1. Validar en juego el fix completo de taint con mUI y Rapzo QoL activos.
2. Probar Target y Focus en V1/V2, con casts, auras, Edit Mode y combate.
3. Confirmar que apagar Unit Frames restaura Player/Target/Focus sin ocultarlos y sin requerir
   `/reload`.
4. Confirmar exactamente una castbar por unidad en V2 y castbars Blizzard normales en V1/OFF.
5. Seguir afinando visualmente V2 con capturas reales; el preview no reemplaza el juego.
6. Verificar el filtro de AH y Customer Orders tras cada cambio de Blizzard.
7. Probar Vendor en Compra/Recompra y con filtros antes de modificar su layout.
8. Mantener este CLAUDE.md al dia al cierre de cada sesion: sumar lo nuevo, borrar lo obsoleto.
9. ReflectHerald: confirmado (2-sep) que el cliente bloquea el registro del CLEU; validar que
   `cleuBlocked` deja el popup en una sola aparicion y probar test, status y retry (seccion 8.10).
10. Crear tag/release alpha5 solo por peticion explicita; el ultimo tag observado sigue siendo
    `v3.0.0-alpha3` aunque el codigo declara alpha5.
11. **Revision completa del 2026-09-10**: ver `INFORME_REVISION_2026-09-10.md` (hallazgos con
    archivo:linea, severidad y fix por modulo, plan por sesiones y dudas a validar en juego).
    Los mas graves: ranuras 11/12 del Vendor invisibles, housing siempre "no obtenido", personaje
    fantasma por reino con apostrofe/espacio, `map()` del Vendor comprando el objeto equivocado,
    CVars de Combat Text no restaurables y Cooldown Pulse perdiendo avisos tras cada reescaneo.
    Este CLAUDE.md aun no documenta los modulos CooldownPulse ni CombatText (TOC, comandos,
    settings); hacerlo al aplicar los fixes.

## 13. Checklist de prueba dentro de WoW

Despues de cambios generales:

1. Ejecutar `/rl`.
2. Revisar errores Lua con BugSack/!BugGrabber o `/console scriptErrors 1`.
3. Ejecutar `/rapzo modules` y `/rapzo status`.
4. Abrir `ESC > Options > AddOns > Rapzo QoL`.
5. Confirmar persistencia de opciones despues de otro `/rl`.

Despues de cambios HUD:

1. Probar aro ON/OFF con Unit Frames ON/OFF.
2. Probar minimapa ON/OFF independientemente.
3. Cambiar V1 -> V2 -> V1 y recargar.
4. Probar Player, Target y Focus.
5. Probar objetivo jugador y objetivo mob para colores.
6. Probar casts del Player, Target y Focus.
7. Probar auras y stacks.
8. Probar una clase con recurso secundario si se toco `ClassResources.lua`.
9. Entrar y salir de combate.
10. Abrir Edit Mode.
11. Repetir con mUI activo.
12. Probar `/rapzo hud preview` y revisar `preview/index.html` si cambio geometria.

Despues de cambios Vendor:

1. Abrir vendedor.
2. Probar todos los filtros.
3. Cambiar tamaño de grilla.
4. Comprar un objeto valido.
5. Abrir Recompra.
6. Cambiar varias veces Compra <-> Recompra.
7. Apagar Vendor y confirmar restauracion nativa sin `/reload`.

Despues de cambios AFK:

1. Probar `/rapzo afk preview` fuera de combate.
2. Cerrar con ESC y con el mismo comando.
3. Entrar en combate mientras esta visible.
4. Probar AFK real y regreso a activo.
5. Confirmar color de clase correcto, incluido Evoker.

Despues de cambios ReflectHerald:

1. Probar `/rapzo reflect test` fuera de grupo y dentro de un grupo.
2. Probar `/rapzo reflect party on|off` y su persistencia tras `/rl`.
3. Provocar un reflejo real con Spell Reflection (guerrero) en una mazmorra.
4. Verificar un solo aviso por reflejo y el contador de `/rapzo reflect stats`.
5. Probar el alias `/rh`.
6. Si el cliente bloquea el CLEU: confirmar que el popup de taint sale a lo sumo una vez, que
   `/rapzo reflect status` dice BLOQUEADO, y que tras `/rl` no reaparece ni el popup ni el aviso.

## 14. Release e instalacion

El workflow `.github/workflows/release.yml` se ejecuta al empujar tags `v*`. Crea un ZIP llamado:

```text
RapzoQoL_<version>_WoW_Retail.zip
```

El ZIP contiene la carpeta unica `RapzoQoL`. El addon no puede actualizarse a si mismo; la
actualizacion ocurre mediante Git/GitHub o un gestor externo.

Instalacion de desarrollo en las dos PCs conocidas:

- IRONSIDE (casa): repositorio normalmente en `D:\PROYECTOS\RAPZOBAGS`.
- TEXTIL LAURA (trabajo): repositorio normalmente en `C:\RAPZOBAGS`.

Aunque las carpetas locales conservan el nombre antiguo, el remoto actual es `RapzoQoL` y el unico
junction dentro de WoW debe apuntar a la subcarpeta `RapzoQoL` del clon.

No asumas que una ruta de IRONSIDE existe en TEXTIL LAURA ni viceversa.

## 15. Reglas finales de continuidad

- Codigo actual > este documento > documentos historicos.
- Una sola rama de trabajo: `main`. Este CLAUDE.md se actualiza al cierre de cada sesion.
- Un solo addon `RapzoQoL`.
- `RapzoBagsDB` no se renombra.
- V1 no se elimina.
- V2 es la linea visual en desarrollo.
- Cursor, minimapa y Unit Frames son independientes.
- No tocar frames protegidos en combate.
- Toda modificacion de Blizzard UI debe ser reversible y registrar el estado original.
- No duplicar hooks, castbars, AuraContainers ni familias de eventos.
- mUI es una compatibilidad prioritaria, especialmente en Target/Focus, auras y castbars.
- Las capturas y pruebas de Rapzo dentro de WoW son la validacion visual final.
- Terminar cada cambio con diff revisado, commit claro y rama remota actualizada.

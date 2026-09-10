# Rapzo QoL - Informe de revision completa (2026-09-10)

> **Estado (misma fecha, por la tarde):** los fixes se aplicaron en tres commits de la rama
> `claude/addon-review-complete-k37k2z` (`a91b68e` sesion 1, `f2b5555` sesion 2, `7c1be20`
> sesion 3). La seccion 7 al final dice que quedo resuelto, que se dejo fuera y por que, y que
> hay que validar en juego. Nada se probo dentro de WoW: solo con un arnes de stubs (Lua 5.1)
> que carga el addon en el orden del TOC, dispara los eventos de login y ejecuta los comandos.

Revision estatica de todo el addon (19 archivos Lua, TOC, preview HTML, workflow y docs) sobre el
commit `44c985c` (`Fix Cooldown Pulse spell detection on WoW 12.1`). En el momento de escribirlo
no se habia modificado codigo: era la lista de trabajo para la siguiente sesion. Cada hallazgo lleva archivo:linea,
severidad, que pasa y como arreglarlo. Las rutas son relativas a `RapzoQoL/`.

Severidades:

- **CRITICO**: rompe una funcion visible o pierde datos.
- **ALTO**: bug real que el usuario nota o que deja el juego/config en mal estado.
- **MEDIO**: bug de borde, rendimiento o reversibilidad incompleta.
- **BAJO**: correcto hoy pero fragil, o API deprecada con fallback.
- **PULIDO**: limpieza, codigo muerto, coherencia.

Lo que se pudo contrastar contra el codigo fuente publico de Blizzard 12.x (wow-ui-source `live`)
se marca con `[Blizzard verificado]`. Lo que solo se puede confirmar dentro de WoW esta en la
seccion 5.

---

## 1. Resumen ejecutivo: los 12 que conviene atacar primero

| # | Sev. | Modulo | Problema en una linea |
|---|------|--------|------------------------|
| 1 | CRITICO | Vendor | Blizzard oculta `MerchantItem11` y `MerchantItem12` al final de cada update y Rapzo nunca los vuelve a mostrar: en la grilla 4x5 hay 2 objetos invisibles por pagina. `[Blizzard verificado]` |
| 2 | CRITICO | Collections | Housing lee `info.quantity`, campo que no existe en `HousingCatalogEntryInfo`: toda decoracion sale como "no obtenida". `[Blizzard verificado]` |
| 3 | ALTO | Core | En `ADDON_LOADED` `GetNormalizedRealmName()` puede ser nil y se crea un personaje fantasma `Nombre-Quel'Thalas` junto al real `Nombre-QuelThalas`; duplica personajes y oro en Search. |
| 4 | ALTO | Vendor | Con filtro activo, `map(index)` cae al indice crudo si el mapa esta desactualizado: se puede comprar el objeto equivocado. |
| 5 | ALTO | CombatText | Los CVars `WorldText*` persisten entre sesiones; la "captura original" se hace tras aplicarlos en la sesion anterior, asi que desactivar/restaurar nunca vuelve a los valores Blizzard. |
| 6 | ALTO | CooldownPulse | Cada reescaneo (`PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, abrir el panel) borra `states`: el primer cooldown que termina despues no avisa. |
| 7 | ALTO | HUD | Cada tick de vida/poder (`UNIT_HEALTH`, `UNIT_POWER_UPDATE`...) re-ejecuta `ApplyFrameStyle` completo (fuentes, anclajes, auras) y `UpdateClassResource` dos veces. Es el mayor coste del addon en combate. |
| 8 | MEDIO | HUD | V2 -> V1 no es reversible sin `/reload`: fuentes Toxi, alto del nombre 10 px y color del power quedan pegados. |
| 9 | MEDIO | HUD | Castbar V2 compara `name == nil` antes de comprobar `issecretvalue`; rompe la regla de CLAUDE.md seccion 4. |
| 10 | MEDIO | Scanner | El escaneo de banco diferido 0.15 s no re-comprueba `bankOpen`: puede guardar un banco vacio si se cierra justo despues de mover el ultimo objeto. |
| 11 | MEDIO | Config/Core | `/rapzo modules`, el contador del panel y el panel propio ignoran `reflectHerald`, `cooldownPulse`, `combatText` y `expansionFilters`. |
| 12 | MEDIO | Docs | CLAUDE.md, README y LEEME no mencionan CooldownPulse ni CombatText (TOC, modulos, comandos, settings). |

Orden sugerido de trabajo: 1, 2, 3, 4 (una tarde de Vendor/Collections/Core), luego 5 y 6
(modulos nuevos), luego 7-9 (HUD, requiere pruebas en juego), y por ultimo 10-12 y el resto.

---

## 2. Hallazgos por modulo

### 2.1 Core (`Core/Core.lua`)

**C-1 [ALTO] Core.lua:38-53, 373-379, 459-462 - Personaje fantasma por reino con espacios/apostrofes.**
`RB:Initialize()` corre en `ADDON_LOADED` y llama `TouchCharacter()`. En ese momento
`GetNormalizedRealmName()` puede devolver nil (solo es fiable desde `PLAYER_LOGIN`) y el fallback
`GetRealmName()` devuelve el nombre con espacios y apostrofes. Resultado en reinos como
Quel'Thalas o Tol Barad: se crea `characters["Nombre-Quel'Thalas"]` con `money` y `lastSeen`, y en
`PLAYER_LOGIN` se crea el real `characters["Nombre-QuelThalas"]`. El fantasma nunca se limpia:
aparece duplicado en la vista de oro de Search y `GetTotalMoney()` suma su oro dos veces.
Fix: (a) no tocar `characters` en `ADDON_LOADED`, mover `TouchCharacter`/`ScanAll` a `PLAYER_LOGIN`;
(b) normalizar siempre la clave en `GetRealmNameSafe` (`realm:gsub("[%s%-']", "")`); (c) una
migracion unica que fusione claves duplicadas del mismo personaje. Comprobar en `/rapzo gold` si ya
existe un duplicado en la DB de Rapzo.

**C-2 [MEDIO] Core.lua:364 - `ShowModules()` lista fija.**
`labels = {"tooltip","search","vendor","collections","afk","hud","expansionFilters","config"}`.
Faltan `reflectHerald`, `cooldownPulse`, `combatText`. `/rapzo modules` no muestra los tres
modulos mas nuevos. Misma omision en `Config.lua:155` (lista del panel) y `Config.lua:598`
(contador "N/M modulos activos").

**C-3 [BAJO] Core.lua:83-92 - Defaults de los modulos nuevos solo por via perezosa.**
`EnsureDB` no declara `modules.cooldownPulse` ni `modules.combatText`; se persisten en la
primera lectura via `IsFeatureEnabled(key, default)`. Declararlos explicitos
(`cooldownPulse = true`, `combatText = false`) junto al resto para que la regla "rellenar solo nil"
quede en un unico sitio.

**C-4 [BAJO] Core.lua:463-465 - `PLAYER_LOGIN` y `PLAYER_ENTERING_WORLD` hacen lo mismo.**
En el login se escanea dos veces seguidas y `ApplyBagDirectionDelayed` programa dos timers cada
vez. Usar solo `PLAYER_ENTERING_WORLD` con `isInitialLogin/isReload` o un flag.

**C-5 [BAJO] Core.lua:415-425 - `/rapzo reset confirm` deja referencias huerfanas.**
Pone `RapzoBagsDB = nil` y recrea la base, pero HUD, Vendor, AFK, etc. ya tienen referencias a
las tablas viejas; hasta el `/reload` escriben en tablas que ya no se guardan. Fix: tras el reset
imprimir "ejecuta /rl" o llamar `ReloadUI()` directamente.

**C-6 [BAJO] Core.lua:445-450 - `/rl` global.**
Cualquier otro addon que registre `/rl` lo pisa o es pisado segun orden de carga. Decision de
diseno; solo documentarlo (ya esta en README).

**C-7 [PULIDO] Core.lua:28 - `RB:Print` hace `tostring(message)`.**
Si algun modulo pasa un valor secreto, explota. Envolver: `if issecretvalue and
issecretvalue(message) then message = "<secreto>" end`.

**C-8 [PULIDO] Core.lua:61 - `db.schema = 5` se escribe incondicionalmente.**
Cuando haga falta una migracion condicionada por version habra que leer el schema ANTES de
sobrescribirlo. Dejar nota o mover la asignacion al final de `EnsureDB`.

**C-9 [PULIDO] Core.lua:98-107 - `IsFeatureEnabled` escribe en la DB en una lectura.**
Combinado con V-4 (Vendor) y A-3 (AFK) son escrituras constantes. Inofensivo pero ruidoso.

### 2.2 Scanner (`Core/Scanner.lua`)

**S-1 [MEDIO] Scanner.lua:213-221, 248-266 - Riesgo de vaciar el banco guardado.**
`ScheduleScan(true)` captura `includeBanks = true` y dispara `ScanBanks` 0.15 s despues sin
re-comprobar `Scanner.bankOpen`. Si `BANKFRAME_CLOSED` llega en ese lapso (mover el ultimo objeto
y cerrar), y el cliente sigue reportando `GetContainerNumSlots > 0` para las pestanas compradas
mientras `GetContainerItemInfo` devuelve nil, `character.bank` / `db.account.bank` se
sobrescriben con tablas vacias. Fix: en el callback `if includeBanks and not Scanner.bankOpen then
includeBanks = false end`, y en `ScanBanks` no reemplazar un bucket que salio vacio de
contenedores con slots > 0.

**S-2 [BAJO] Scanner.lua:146-153 - Fallback de indices de banco desactualizado. `[Blizzard verificado]`**
`Enum.BagIndex` en 12.x es: `Accountbanktab=-3, Characterbanktab=-2, Keyring=-1, Backpack=0,
Bag_1..4=1..4, ReagentBag=5, CharacterBankTab_1..6=6..11, AccountBankTab_1..5=12..16`. Ya no
existen `Bank=-1`, `Reagentbank=-3` ni `Bankbag_1..7=6..12`. El fallback `-1, -3, 6..12` solo se
usa si el enum falta, pero si se usara contaria el llavero (-1) y la pestana 1 del banco de banda
(12) como banco de personaje. La deteccion por nombre (lineas 135-144) SI acierta con el enum real.
Fix: fallback `6..11` personaje y `12..16` cuenta, o eliminarlo. Actualizar tambien los numeros de
CLAUDE.md seccion 8.2 si se mencionan.

**S-3 [BAJO] Scanner.lua:229-241 - Eventos inexistentes y uno util ausente.**
`ACCOUNT_BANK_PANEL_OPENED/CLOSED`, `ACCOUNT_BANK_TAB_SLOTS_CHANGED`,
`PLAYERBANKBAGSLOTS_CHANGED`, `PLAYERREAGENTBANKSLOTS_CHANGED` no existen en 12.x; el pcall los
traga en silencio. Los reales: `BANKFRAME_OPENED/CLOSED`, `PLAYERBANKSLOTS_CHANGED`,
`PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`, `BANK_TABS_CHANGED`, `BANK_TAB_SETTINGS_UPDATED`. Comprar
una pestana nueva (`BANK_TABS_CHANGED`) hoy no reescanea. Fix: limpiar la lista y anadir
`BANK_TABS_CHANGED`.

**S-4 [BAJO] Scanner.lua:248-266 - Sin debounce.**
`PLAYERBANKSLOTS_CHANGED` dispara por ranura; cada uno crea un timer que hace `ScanAll` completo.
`BAG_UPDATE_DELAYED` escanea el inventario sincrono y otra vez en el timer. Fix: flag
`scanPending` y un solo timer.

**S-5 [BAJO] Scanner.lua:268 + Core.lua:378 - Escaneo en `ADDON_LOADED`.**
Sobrescribe `bags`/`equipped` con buckets posiblemente vacios antes de que el cliente tenga datos;
se corrige en `PLAYER_LOGIN`, pero es trabajo inutil y alimenta C-1. Fix: en `Initialize` solo
registrar eventos.

**S-6 [PULIDO] Scanner.lua:171-178 - Equipo 1..19.**
Ignora herramientas de profesion (slots 20..31). Decision de diseno; documentar.

### 2.3 Tooltip (`Modules/Tooltip/Tooltip.lua`)

**T-1 [PULIDO] Tooltip.lua:297-299 - Limite de personajes hardcodeado para objetos ligados.**
`boundLimit = ... 8 or 4` ignora `settings.maxCharacters` (documentado como 12) sin avisar.
Exponerlo como setting o usar el configurado.

**T-2 [PULIDO] Tooltip.lua:261-264 - Primer tooltip inconsistente.**
Si el objeto no esta cacheado, `metadata.bindType` es nil -> `characterBound = false` y el primer
tooltip muestra "En tu cuenta" + Total; el siguiente ya muestra la variante ligada. Se autocorrige;
si molesta, pedir `RequestLoadItemDataByID` y no pintar el bloque hasta tener bindType.

**T-3 [PULIDO] Tooltip.lua:201-218 vs Search.lua:36-67 - Doble desempaquetado de `C_Item.GetItemInfo`.**
Centralizar un `RB:GetItemInfoTable(itemID)` en Core.

**T-4 [DUDA] Tooltip.lua:151-177 - Parche mUI.**
Reemplaza `style.OnTooltipSetItem` en la tabla; si mUI registro un closure directamente en
`TooltipDataProcessor`, el reemplazo no lo intercepta. Solo verificable con mUI activo.

Lo que esta bien: `TooltipDataProcessor.AddTooltipPostCall` con `issecretvalue` sobre `data.id` y
el link, sin duplicar lineas; el commit `a729616` (objetos ligados) es coherente.

### 2.4 Search (`Modules/Search/Search.lua`)

**SE-1 [MEDIO] Search.lua:99-128 - Coste por busqueda proporcional a objetos x personajes.**
Para cada ID de `GetAllKnownItemIDs()` se llama `GetKnownItemLink` (recorre todos los personajes y
crea una tabla `{"bags","equipped","bank"}` por iteracion en `Core.lua:317`), `itemDisplayName`
-> `C_Item.GetItemInfo` + `RequestLoadItemDataByID` por objeto no cacheado, y `GetItemAggregate`
(otro recorrido completo). Con `/rapzo` sin texto se procesa todo el inventario y se lanza una
rafaga de peticiones al servidor. Fix: sacar el nombre del link guardado
(`link:match("%[(.-)%]")`) y pedir `GetItemInfo` solo para filas visibles/detalle; una sola pasada
de agregados por busqueda.

**SE-2 [BAJO] Search.lua:427-433 - `/rapzo search` sin texto no enfoca la caja.**
Core pasa `""` (truthy), asi que entra en `frame.edit:SetText(query)` sin `SetFocus`. Fix:
`if query and query ~= "" then`.

**SE-3 [BAJO] Search.lua:28-34 (y AFK.lua:169-176) - `GetCoinTextureString` deprecado.**
Vive en `Blizzard_DeprecatedCurrencyScript`. Usar `C_CurrencyInfo.GetCoinTextureString` con
fallback al global.

**SE-4 [PULIDO] Search.lua:454-463 - `Search:ShowStatus` es codigo muerto.**

### 2.5 Collections (`Modules/Collections/Collections.lua`)

**CO-1 [CRITICO] Collections.lua:116-121 - Housing siempre "no obtenido". `[Blizzard verificado]`**
`return (tonumber(info.quantity) or 0) > 0, "Decoracion"`. `HousingCatalogEntryInfo` en 12.x
tiene `totalNumStored`, `totalNumPlaced`, `remainingRedeemable`, `destroyableInstanceCount`...
pero NO `quantity` (ese campo esta en `HousingBundleDecorEntryInfo`). Toda decoracion se marca no
obtenida, nunca sale `OBTENIDO` y el filtro "No obtenidos" las muestra siempre.
Fix: `local owned = (tonumber(info.totalNumStored) or 0) + (tonumber(info.totalNumPlaced) or 0);
return owned > 0, "Decoracion"`.

**CO-2 [MEDIO] Collections.lua:155-158 (+ Vendor.lua:849-898) - Tormenta de rebuilds por `GET_ITEM_INFO_RECEIVED`.**
Ambos modulos hacen `wipe(cache)` completo por cada objeto que llega; Vendor ademas ejecuta
`BuildFilteredIndices()` (que llama `C_TooltipInfo.GetItemByID` por objeto -> mas peticiones ->
mas eventos) y agenda un `C_Timer.After(0.05, MerchantFrame_Update)` por evento sin coalescer. Con
un vendedor de 60 objetos sin cachear son decenas de `MerchantFrame_Update` seguidos. Fix: en
Collections invalidar solo `cache[itemID]` del evento; en Vendor un flag `pendingRefresh` con un
unico timer.

**CO-3 [BAJO] Collections.lua:129-147 - Cachea negativos de objetos no cargados.**
`GetMountFromItem`/`GetToyInfo`/`GetItemLearnTransmogSet` devuelven nil hasta que el objeto esta
cargado; se guarda `{collected=false}` y se depende del wipe global. Fix: no cachear si
`C_Item.IsItemDataCachedByID(itemID)` es false.

**CO-4 [BAJO] Collections.lua:18 - `Enum.TooltipDataLineType.RestrictedSpellKnown` no existe en 12.x. `[Blizzard verificado]`**
La rama compara con nil y es codigo muerto; la deteccion de "ya conocido" depende solo de
`line.leftText == ITEM_SPELL_KNOWN`. Fix: eliminar esa rama y proteger la comparacion de texto
con `issecretvalue(line.leftText)`.

Lo que esta bien: los desplazamientos por pcall en `getPetState` (`speciesID = results[14]`),
`getMountState` (`isCollected = values[12]`), `getRecipeState` (`classID = values[7]`) y
`getTransmogSetState` (`appearance.itemID`) son correctos para 12.x.

### 2.6 Vendor (`Modules/Vendor/Vendor.lua`)

**V-1 [CRITICO] Vendor.lua:547-566, 672-676 - Ranuras 11 y 12 invisibles. `[Blizzard verificado]`**
`MerchantFrame_UpdateMerchantInfo` de 12.x termina con un bloque incondicional:
```lua
-- Hide buyback related items
MerchantItem11:Hide();
MerchantItem12:Hide();
BuybackBG:Hide();
```
El post-hook de Rapzo (`LayoutMerchantSlots`) solo hace `ClearAllPoints/SetPoint`, y en todo
Vendor.lua no hay ningun `Show()` sobre un slot. Con la grilla 4x5 (`MERCHANT_ITEMS_PER_PAGE = 20`)
los objetos con indice visible 11 y 12 de CADA pagina existen para la paginacion pero no se ven ni
se pueden comprar desde la grilla (hueco en la fila 3). Fix: al final de `LayoutMerchantSlots`,
para `index = 1, total`, si `frame.ItemButton:IsShown()` (Blizzard deja el ItemButton visible
cuando hay objeto) hacer `frame:Show()`; y en `RestoreDefaultMerchantLayout` volver a ocultar 11/12.
Probar en juego: un vendedor con mas de 12 objetos debe llenar la fila 3 completa.

**V-2 [ALTO] Vendor.lua:212-217, 234-239, 863-881 - El mapeo filtrado cae al indice crudo.**
`map(index)` devuelve `Vendor:MapVisibleIndex(index) or index`. Con filtro activo, si
`filteredIndices[index]` es nil (mapa desactualizado), `BuyMerchantItem`/`PickupMerchantItem`
reciben el indice visible como si fuera real. La ventana existe: en el handler,
`BuildFilteredIndices()` es sincrono pero `MerchantFrame_Update()` se difiere 0-50 ms; con
`NEW_MOUNT_ADDED`/`TRANSMOG_COLLECTION_UPDATED` la lista "No obtenidos" se acorta y los botones aun
muestran el objeto viejo con `GetID()` viejo. Un clic en esa ventana compra otro objeto.
Fix: que `map` devuelva nil sin mapeo y que los wrappers de compra no hagan nada (y disparen
refresh); o mover `BuildFilteredIndices()` dentro del callback del timer, justo antes de
`MerchantFrame_Update()`, para que mapa y botones cambien a la vez.

**V-3 [MEDIO] Vendor.lua:471-495, 678-681 - Hook de Recompra no inerte y pisa el espaciado nativo. `[Blizzard verificado]`**
`hooksecurefunc("MerchantFrame_UpdateBuybackInfo", ...)` solo comprueba `Vendor.ready`, no
`cfg.enabled`. Blizzard, dentro de `UpdateBuybackInfo`, ancla `MerchantItem3/5/7/9` con offset
`-15`; Rapzo reaplica inmediatamente `originalSlotPoints` (capturados en Compra, con `-8`), asi que
la pestana Recompra queda con espaciado de Compra incluso con el modulo OFF. Fix: `if not
getConfig().enabled then return end` al inicio; en Recompra no reanclar 3/5/7/9, solo restaurar
1,2,4,6,8,10,11,12, ocultar 13+, ocultar la barra de filtros y restaurar tamano.

**V-4 [MEDIO] Vendor.lua:77-92 - `getConfig()` escribe en DB y clampa en cada API envuelta.**
`IsFilterActive()` -> `getConfig()` -> `RB:EnsureDB()` + dos clamps + `RB:SetFeatureEnabled(...)`.
Se invoca desde `GetMerchantNumItems`, `map()`, `MapVisibleIndex`, `ItemMatchesFilter`: cientos de
veces por `MerchantFrame_Update`. Fix: cachear `cfg` en `Vendor.cfg`; los wrappers leen la cache;
sincronizar `modules.vendor` solo en `SetEnabled`.

**V-5 [MEDIO] Vendor.lua:150-189, 446-448 - Override permanente del `OnEnter` nativo.**
`CaptureOriginalLayout` llama `PrepareSlot` sobre `MerchantItem1..12` aunque `cfg.enabled ==
false`, y `PrepareSlot` hace `ItemButton:SetScript("OnEnter", showTooltip)` sin guardar ni
restaurar el original. Hoy `showTooltip` equivale a `MerchantItemButton_OnEnter`, pero es una
modificacion no reversible que sigue activa con Vendor OFF. Fix: guardar
`ItemButton:GetScript("OnEnter")`; si `not cfg.enabled` delegar al original; restaurar en
`SetEnabled(false)`.

**V-6 [BAJO] Vendor.lua:577-580 - `MerchantFrameInset:ClearPoint("RIGHT")` + `SetPoint` no reversible.**
El Inset se ancla por TOPLEFT/BOTTOMRIGHT: `ClearPoint("RIGHT")` no borra nada y el `SetPoint`
anade un tercer anclaje que `RestoreDefaultMerchantLayout` nunca quita. Fix: eliminarlo (el ancho
ya lo da `MerchantFrame:SetSize`) o guardar/restaurar.

**V-7 [BAJO] Vendor.lua:190-205 - Sin clamp de pagina al filtrar.**
Si el conteo filtrado baja, `MerchantFrame.page` puede quedar en una pagina vacia. Fix: en
`BuildFilteredIndices`, `MerchantFrame.page = math.max(1, math.min(page, math.ceil(#filtered /
MERCHANT_ITEMS_PER_PAGE)))`.

**V-8 [BAJO] Vendor.lua:86, 118 - `showOwnedCount` sin comando ni checkbox.**
Solo se cambia editando la SavedVariable. Anadir `/rapzo vendor owned on|off`.

**V-9 [BAJO] Vendor.lua:140 - `"✓ OBTENIDO"` usa U+2713.**
Las fuentes por defecto de WoW no lo tienen (mismo problema que CLAUDE.md documenta para emojis).
Fix: ASCII (`OBTENIDO` a secas o `[OK]`) o una textura.

**V-10 [PULIDO] Vendor.lua:563-566** - `if frame and i > total` es redundante (el bucle empieza en
`total + 1`). **Vendor.lua:215, 241-243** - `GetMerchantItemInfo` ya no existe como global en 12.x;
el wrapper es inerte y se puede borrar.

Lo que esta bien: el conjunto de APIs envueltas en `WrapMerchantAPIs` cubre exactamente lo que
`MerchantFrame_UpdateMerchantInfo` de 12.x llama, y el hook de `MerchantFrame_UpdateAltCurrency`
remapea `button.index` correctamente. Blizzard resetea desaturacion y color del nombre en cada
update, asi que el marcado de Rapzo no deja residuos.

### 2.7 Filtro de expansion (`Modules/QoL/ExpansionFilters.lua`)

**E-1 [PULIDO] ExpansionFilters.lua:132-134 - Hook de mixin inerte.**
`hooksecurefunc(AuctionHouseSearchBarMixin, "OnShow", ...)` se instala cuando el frame ya copio el
metodo (el comentario de la linea 137 lo reconoce). El `HookScript("OnShow")` de la 143 es el que
funciona; el del mixin solo aporta doble aplicacion. Eliminarlo o dejarlo como fallback documentado.

**E-2 [DUDA] ExpansionFilters.lua:45-56, 94-98** - Escribir en `filterButton.filters[...]` /
`dropdown.filters[...]` desde addon "mancha" esas tablas. Historicamente `SendBrowseQuery` no es
protegida; si 12.x la protege, la busqueda se bloquearia con popup de taint (no con error Lua).
`_G.g_auctionHouseFilters` (linea 45) no es una global conocida de Blizzard; esta protegida por
`type()`.

**E-3 [PULIDO] ExpansionFilters.lua:224** - `events:RegisterEvent("ADDON_LOADED")` directo en vez de
`RB:RegisterEventSafe`.

### 2.8 AFK (`Modules/AFK/AFK.lua`, `AFKBrand.lua`)

**A-1 [MEDIO] AFK.lua:121-137 (y ClassResources.lua:24-35) - Solo usa las globales deprecadas de especializacion.**
`GetSpecialization`/`GetSpecializationInfo` viven en `Blizzard_Deprecated` desde 11.1.5; el API es
`C_SpecializationInfo.GetSpecialization()` / `GetSpecializationInfo()`. CooldownPulse.lua:271-287
ya lo hace bien. Si la global desaparece, la spec deja de aparecer en la tarjeta AFK y Feral,
Windwalker y Arcane pierden la fila de recurso, todo en silencio. Fix: probar primero
`C_SpecializationInfo` con fallback a la global.

**A-2 [PULIDO] AFKBrand.lua (archivo completo) - Es un no-op.**
`frame.logo` ya nace con alpha 0 y 1x1 (AFK.lua:236-240), `frame.RapzoQoLBadge` nunca se crea, la
cita ya es identica y el footer nunca contiene "RapzoBags". Solo anade un `hooksecurefunc` que hace
un `gsub` cada segundo. Se puede borrar el archivo, su linea del TOC y su mencion en CLAUDE.md
secciones 5 y 8.8.

**A-3 [PULIDO] AFK.lua:88-107 - `getConfig()` escribe en cada lectura.**
Ejecuta `RB:SetFeatureEnabled("afk", cfg.enabled, true)` en CADA llamada (cada tick del
temporizador, cada evento). Si alguien cambia solo `modules.afk`, la siguiente `getConfig()` lo
revierte. Hacer que `AFK:SetEnabled` sea el unico escritor.

Lo que esta bien: manejo de `UnitIsAFK` secreto (72-86, 564-573, reintento a 2 s sin ramificar),
`PLAYER_FLAGS_CHANGED` con unidad secreta (692-699), preview sin fantasma (619-628), guard de
combate en `ShowScreen`/`TogglePreview`.

### 2.9 ReflectHerald (`Modules/ReflectHerald/ReflectHerald.lua`)

**R-1 [MEDIO] ReflectHerald.lua:95-103 - Ventana de atribucion de 5 s demasiado ancha.**
El intento de registrar el CLEU ocurre en `PLAYER_LOGIN`, justo cuando HUD/Vendor/AuraAnchors
hacen su trabajo inicial. Cualquier `ADDON_ACTION_BLOCKED` de Rapzo QoL en esos 5 s (un `SetPoint`
en frame protegido, por ejemplo) queda atribuido al CLEU y PERSISTE `cleuBlocked = true` hasta un
`retry` manual. Fix: reducir la ventana a ~1 s, guardar `arg2` (nombre de la funcion bloqueada) en
`settings.reflectHerald.lastBlockedFunc` para poder afinar con el proximo taint.log, y no persistir
el flag si `arg2` claramente no es `RegisterEvent`/`pcall`.

**R-2 [DUDA] ReflectHerald.lua:46-49** - `pcall(SendChatMessage, ...)`: si Midnight bloquea chat
iniciado por addon en instancias (AFK.lua:561 ya menciona un "chat messaging lockdown"), el bloqueo
llega como popup de taint y el pcall no lo ve. Probar `/rapzo reflect test` dentro de un grupo en
mazmorra antes de dar por valido el anuncio.

Lo que esta bien: el destructuring de `CombatLogGetCurrentEventInfo()` (spellName en 13, missType
en 15) es correcto para `SPELL_MISSED`; todo va dentro del pcall; el retry imprime con 2 s de
retraso como documenta CLAUDE.md.

### 2.10 Cooldown Pulse (`Modules/CooldownPulse/CooldownPulse.lua`) - NO documentado en CLAUDE.md

**P-1 [ALTO] CooldownPulse.lua:294-297, 376-385, 793-796, 979-984 - Cada reescaneo borra las mediciones en curso.**
`ScanSpells` -> `clearCatalog()` -> `wipe(states)`. Se dispara en `PLAYER_ENTERING_WORLD` (cada
pantalla de carga), `SPELLS_CHANGED` (muy frecuente: formas de druida, monturas, vehiculos, cambios
de zona), `TRAIT_CONFIG_UPDATED`, `ACTIVE_TALENT_GROUP_CHANGED` y CADA vez que se abre el panel
(`OnShow` -> `ScanSpells(false)`). Tras el rescan, `addSpell` deja `startedAt = nil` y
`handleEntry` hace `if not startedAt then return end`: todo cooldown que estaba corriendo termina
sin aviso. Un druida cambiando de forma en combate pierde alertas constantemente; entrar a una
mazmorra tras usar un CD de 3 min tampoco avisa. Fix: en `ScanSpells` conservar `states[key]` de
las claves que siguen presentes (`local keep = states; states = {}; ... states[key] = keep[key] or
{...}`), y en el `OnShow` del panel rescanear solo si `#catalog == 0`.

**P-2 [MEDIO] CooldownPulse.lua:423-461 - Aviso adelantado por GCD y cargas sin tratar.**
`running = active and not onGCD`. Si a un cooldown real le quedan menos de 1.5 s y se lanza otro
hechizo, el API reporta el GCD (`isOnGCD = true`) -> `running = false` -> transicion ON->OFF -> el
pulso salta ~1 s ANTES de que el poder sea lanzable. Ademas no usa `C_Spell.GetSpellCharges`:
con hechizos de cargas `isActive` permanece true mientras se recargan cargas consecutivas, se
aprende 2x-3x la duracion real (learnDuration guarda el MAXIMO) y solo avisa al volver la ultima
carga. Fix: iniciar la medicion con `active and not onGCD`, pero cerrarla solo con `not active`;
guardar la ULTIMA duracion medida (o media) en vez del maximo; consultar `GetSpellCharges` para
avisar por carga o al menos documentar el comportamiento.

**P-3 [MEDIO] CooldownPulse.lua:182-214, 228 - El icono se desplaza durante la animacion.**
El frame esta anclado con `SetPoint("CENTER", UIParent, "CENTER", s.x, s.y)` y se anima con
`SetScale(0.68..1.10)`; los offsets se interpretan en la escala del frame, asi que con `y = 145` el
icono aparece ~46 px mas abajo y se desliza hacia arriba durante el pop-in. Fix: un frame
contenedor sin escala como ancla y un hijo interior que hace `SetScale/SetAlpha`.

**P-4 [MEDIO] CooldownPulse.lua:463-473, 940-946, 985-989 - Coste por frame.**
`pollCooldowns` recorre todo el catalogo (30-60 hechizos) 10 veces por segundo Y en cada
`SPELL_UPDATE_COOLDOWN` (varias veces por segundo en combate): 600-1200
`pcall(C_Spell.GetSpellCooldown)`/s. El OnUpdate ademas llama `isEnabled()` -> `EnsureDB()` cada
frame incluso con el modulo OFF, y `getSettings()` (clamps y asignaciones) en cada poll. Fix:
cachear `enabled` y la tabla de settings (refrescar en `SetEnabled`/slash); `POLL_INTERVAL = 0.25`
y, tras un poll por evento, saltar el siguiente tick.

**P-5 [BAJO] CooldownPulse.lua:105-117 - Si `isActive`/`isOnGCD` no existen, fallo silencioso.**
`active = info.isActive and true or false`: en un cliente sin ese campo `active` es siempre false y
el modulo no avisa jamas mientras `status` dice "N detectados". Las expresiones estan fuera del
pcall. Fix: si `info.isActive == nil` caer a `plain(info.duration) > 0` (y `duration <= 1.5` como
GCD), proteger con `issecretvalue`, y reportar el "modo de deteccion" en `PrintStatus`.

**P-6 [BAJO] CooldownPulse.lua:336-371 - Raciales excluidos.**
Con `coreOnly = true` solo entran las lineas cuyo nombre coincide con clase/spec; Blood Fury,
Berserking, Arcane Torrent estan en "General" y nunca avisan. Sugerencia: incluir "General" pero
filtrar por `baseCooldownHint > 0`.

**P-7 [PULIDO]** CooldownPulse.lua:94-102, 324: `baseCooldownHint` se calcula con dos pcall por
hechizo y nunca se lee; `readCooldown` devuelve `duration` y nadie la usa. Linea 353:
`GetSpellBookSkillLineInfo` sin pcall mientras `GetSpellBookItemInfo` si lo lleva. Lineas 682/684:
"·" no ASCII. No hay toggle en el panel propio `RapzoQoLConfigFrame` (solo subcategoria Blizzard y
`/rapzo pulse`).

Lo que esta bien: medir con `GetTime()` sobre `isActive/isOnGCD` en vez de numeros es la
estrategia correcta para Midnight; el fix de `offSpecID == 0` (commit 44c985c) es correcto (0 es
truthy en Lua) y el fallback de scan sin filtro de linea es acertado; `C_Spell.GetSpellInfo` en
forma de tabla y `C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)` son el
API vigente.

### 2.11 Combat Text (`Modules/CombatText/CombatText.lua`) - NO documentado en CLAUDE.md

Aclaracion previa: el modulo NO dibuja numeros propios ni toca el combat log (no comparte el
bloqueo del CLEU). Solo cambia `DAMAGE_TEXT_FONT`, los CVars `WorldTextScale/Gravity/RampDuration`
y los objetos de fuente `CombatTextFont` etc. El commit lo llama "NiceDamage-style" y promete mas de
lo que hace; conviene ajustar nombre/descripcion.

**CT-1 [ALTO] CombatText.lua:114-121, 199-205, 238-243 - La restauracion nunca vuelve a Blizzard.**
`captureOriginal()` toma la foto en `PLAYER_LOGIN` de cada sesion. `WorldTextScale` y compania
son CVars PERSISTENTES (Config.wtf). Si el modulo estuvo ON con escala 2.0, al siguiente login la
"original" ya es 2.0; desactivar, "Restaurar sesion" y `/rapzo damage restore` "restauran" a 2.0.
Desinstalar el addon tampoco lo arregla. Fix: persistir la foto pristina UNA sola vez en
`settings.combatText.pristine` (capturada antes de aplicar por primera vez) y restaurar desde ahi;
como red de seguridad usar `C_CVar.GetCVarDefault(name)` si no hay foto.

**CT-2 [MEDIO] CombatText.lua:251, 606-619 - Momento de asignar `DAMAGE_TEXT_FONT`.**
Se asigna por primera vez en `PLAYER_LOGIN`. El motor lee ese global al inicializar el texto de
mundo; NiceDamage/ElvUI lo asignan lo antes posible. Las SavedVariables ya estan disponibles en
`ADDON_LOADED` del propio addon. Fix: aplicar la fuente 3D tambien desde `ADDON_LOADED` (por
ejemplo desde `RB:Initialize()`), mantener el reapply en `PLAYER_LOGIN`, y comprobar en juego si
con eso basta un `/rl` en vez de salir a seleccion de personaje.

**CT-3 [MEDIO] CombatText.lua:23-36 - Nombres de CVars/font objects no verificados, fallo silencioso.**
`WorldTextGravity`, `WorldTextRampDuration`, las variantes `_v2`, `DamageNumberFont` y `WorldFont`
se aplican con pcall/guard: si no existen no hay error ni efecto, y `PrintStatus` dice ON. Fix:
validar con `C_CVar.GetCVarInfo(name)` / `GetCVar` cuales existen, quitar los que no, y mostrar en
status cuantos CVars/objetos se aplicaron realmente.

**CT-4 [BAJO] CombatText.lua:474-486 - Posible recorte en el canvas de Blizzard Settings.**
Botones en `y = -610` y status en `-650` con anclajes absolutos; el canvas no tiene scroll. Verificar
en juego; si se corta, compactar o meter un ScrollFrame como hace CooldownPulse.

**CT-5 [PULIDO]** Usa LibStub/LibSharedMedia si estan presentes (CLAUDE.md seccion 4 dice "sin
LibStub"): es opcional y esta bien, pero documentarlo. El callback LSM solo se intenta en carga
(624-631). "Restaurar sesion" no desactiva el modulo: en el siguiente `PLAYER_ENTERING_WORLD` se
vuelve a aplicar (es lo documentado, pero decirlo en el boton).

### 2.12 HUD (`Modules/HUD/*.lua`)

**H-1 [ALTO] HUDStyles.lua:789-793 + HUD.lua:936-941, 985-995 + ClassResources.lua:393-408 - Cada tick re-ejecuta la tuberia completa de estilo.**
HUD.lua registra `UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_POWER_UPDATE`, `UNIT_MAXPOWER`,
`UNIT_DISPLAYPOWER`, `UNIT_NAME_UPDATE` y por cada uno llama `HUD:UpdateUnitFrames(unit)`.
HUDStyles engancha esa funcion con `hooksecurefunc(HUD, "UpdateUnitFrames", ... ApplyFrameStyle)`,
y `applyStyle2` hace en cada llamada: `SetScale`, ~12 `ClearAllPoints/SetPoint`,
`applyToxiTypography` (5 x `SetFont`, operacion cara), 3 x `setEdgesColor`,
`setPlayerAurasEnabled` -> `container:UpdateAllAuras()`, re-anclado del AuraContainer y
`updateCastBar`. ClassResources engancha DOS veces (`ApplyFrameStyle` y `UpdateUnitFrames`) ->
`UpdateClassResource` corre dos veces por evento, mas una tercera por su propio handler de
`UNIT_POWER_UPDATE/FREQUENT`; cada pasada hace `layoutPips` (10 x `ClearAllPoints/SetPoint/SetSize`)
y `HUD:GetStyle()` (que llama `RB:EnsureDB()` completo) ~8 veces. Con un DPS de energia/mana en
combate son decenas de relayouts por segundo.
Fix: separar "estilo" de "valores". `UpdateUnitFrames` solo escribe
`SetValue/SetText/SetStatusBarColor`. `ApplyFrameStyle` solo en creacion, cambio de estilo/escala,
`PLAYER_TARGET_CHANGED`/`PLAYER_FOCUS_CHANGED` y `PLAYER_REGEN_ENABLED`. Quitar el hook de
`UpdateUnitFrames` en HUDStyles (790) y uno de los dos de ClassResources (403-408); cachear
`getResourceDef()` en `PLAYER_SPECIALIZATION_CHANGED` y no reconstruir pips si `maximum` no cambio.

**H-2 [MEDIO] HUD.lua:936-941, HUDStyles.lua:804-816, ClassResources.lua:419-421 - Eventos `UNIT_*` sin filtro de unidad.**
Se reciben para TODAS las unidades (raid, party, nameplates, arena) y se descartan comparando
strings. En raid/M+ multiplica x20-40 las llamadas al handler. Fix:
`frame:RegisterUnitEvent("UNIT_HEALTH", "player", "target", "focus")` dentro de pcall (anadir
`RB:RegisterUnitEventSafe`); en ClassResources basta `"player"`.

**H-3 [MEDIO] HUDStyles.lua:572-601, 660-668, 694-702 vs 603-640 - V2 -> V1 no es reversible sin `/reload`.**
`applyStyle2` cambia cosas que `applyStyle1` nunca restaura: fuentes via `applyToxiTypography`
(`SetFont(STANDARD_TEXT_FONT, 9/8/10, "OUTLINE")` sobre nombre, vida, poder y nivel),
`nameText:SetHeight(10)` (V1 lo creo con 14 en HUD.lua:408), `power:SetStatusBarColor(0.11,
0.14, 0.18)` (V1 solo restaura bordes, no el relleno `COLORS.power`) y los fondos de health/power
(V1 no restaura el 0.96 de `createBar`). Tras `style 2` y luego `style 1`, V1 queda con tipografia
Toxi, nombre recortado a 10 px y power mas oscuro. El checklist de CLAUDE.md dice "V1 -> V2 -> V1 y
recargar", lo que sugiere que ya se noto. Fix: en `applyStyle1` restaurar explicitamente
`nameText:SetFontObject("GameFontHighlight")` + `SetHeight(14)`,
`healthPercentText/healthValueText:SetFontObject("GameFontHighlightSmall")`,
`powerValueText:SetFontObject("GameFontDisableSmall")`, `levelText:SetFontObject("GameFontNormalSmall")`,
`power:SetStatusBarColor(0.22, 0.28, 0.38)` y los `RapzoQoLBackground:SetColorTexture` originales.
Mas robusto: snapshot de fuentes/colores en `createUnitDisplay` y restaurarlo.

**H-4 [MEDIO] HUDStyles.lua:264-276, 293 - Comparacion directa de posibles valores secretos en la castbar V2.**
`name = UnitCastingInfo(unit)` ... `if name == nil then bar:Hide() return end`. En 12.x el nombre
del cast de un enemigo en contenido instanciado puede ser secreto; el archivo ya tiene `setCastText`
con `isSecret` (237-244) pero la decision "hay cast o no" compara antes de comprobar. HUD.lua lo
hace bien en `setSecretSafeText` (159) y `UnitLevel` (549). Fix:
```lua
local ok, n = pcall(UnitCastingInfo, unit)
local casting = ok and (isSecret(n) or n ~= nil)
-- idem para UnitChannelInfo y para duration: `if isSecret(duration) or duration ~= nil`
```
Extra: `UnitCastingInfo` devuelve `notInterruptible` (8.o valor) que V2 ignora; se podria pintar
la barra en gris.

**H-5 [MEDIO] ClassResources.lua:24-35 - `GetSpecialization` globales deprecadas** (ver A-1).

**H-6 [MEDIO] preview/index.html:143-148, 113 vs HUDStyles.lua:11-18 - El preview offline no coincide con V2.**
HUDStyles: V2 = 150x43 a escala 1.50 (=225x65), health 21 px en y=-11, power 9, auras 16 px. El
HTML: `body.style2 .frame{width:296px;height:72px}`, `.health{top:25px}` con `height:24px`, `.aura`
20x20. CLAUDE.md seccion 9.7 exige mantenerlos alineados. Fix: CSS de `.style2` a 150x43 con
`transform:scale(1.5)`, health 21@-11, power 9@-1, auras 16 px gap 5, castbar 10 px a -4.

**H-7 [BAJO] HUDPreview.lua:261-333 - El preview in-game V1 queda contaminado tras ver V2.**
La rama V2 hace `health:SetHeight(21)` y `nameText:SetHeight(10)`; la rama V1 reposiciona pero no
restaura `SetHeight(24)` ni `SetHeight(14)`. El power del preview se crea con 9 px (linea 154)
mientras V1 real usa 10 (HUD.lua:437), y las constantes `STYLE2_*` estan duplicadas (8-10) en vez
de exportadas por HUDStyles. Fix: restaurar alturas en la rama V1; exponer `HUD.STYLE2 = {width=150,
height=43, aura=16, auraY=18}` desde HUDStyles y consumirlo en Preview.

**H-8 [BAJO] HUD.lua:245-246 vs HUDFixes.lua:186-201 - Doble tratamiento del arte contextual del PlayerFrame.**
`hidePlayerStaticArt` pone a alpha 0 TODO `PlayerFrameContentContextual` (oculta tambien marcador
de raid, lider, rol y PvP del jugador; en Target/Focus se conservan deliberadamente). HUDFixes vuelve
a atenuar hijos de ese mismo contenedor con su propia tabla `restArtAlpha`. Fix: un unico dueno.
Recomendado: en HUD.lua ocultar solo `PrestigePortrait/PrestigeBadge/PlayerPortraitCornerIcon/
AttackIcon/PlayerRestLoop` y dejar visible el resto; en HUDFixes solo `StatusTexture`.

**H-9 [BAJO] HUD.lua:741, 750-752, 818 - Minimapa: mascara no restaurable y globales muertos.**
`Minimap.SetMaskTexture(WHITE_TEXTURE)` no se revierte (el mensaje pide `/reload`).
`MinimapBorderTop` y `MiniMapTrackingBorder` no existen en 10.x+ (`MinimapCluster.BorderTop`,
`MinimapCluster.Tracking`): no-ops. Fix: en `RestoreMinimapArt` probar
`Minimap:SetMaskTexture("Textures\\MinimapMask")` y, si funciona en juego, quitar el aviso de
`/reload`; sustituir los globales muertos.

**H-10 [BAJO] HUDFixes.lua:112-123 - Un frame de parpadeo de la castbar nativa por cast en V2.**
`CastingBarMixin` hace `SetAlpha(1)` y `Show()` al empezar un cast; el hook `OnShow` difiere la
reconciliacion con `C_Timer.After(0, ...)`, asi que la barra nativa se pinta un frame con alpha 1.
Fix: aplicar `SetAlpha(0)` inmediato en el hook (no es protegido) y dejar el timer como confirmacion.

**H-11 [BAJO] HUD.lua:603-606 - Guard de combate innecesario en `CreateUnitDisplays`.**
Crear frames inseguros y cambiar alpha esta permitido en combate. Si se hace `/rapzo hud frames on`
en combate con displays ya creados, el arte nativo sigue visible hasta `PLAYER_REGEN_ENABLED`.
Fix: quitar el guard o limitarlo a las partes que lo requieran (ninguna aqui).

**H-12 [BAJO] HUD.lua:703-727 - OnUpdate del aro llama `SetSize` tres veces por frame.**
El tamano solo cambia con `/rapzo hud cursorsize`. Fix: aplicar tamanos en `Apply()`/`SetPart` y en
OnUpdate solo mover el punto.

**H-13 [BAJO] HUDPreview.lua:195, 201, 367, 424-430 - Pequenos riesgos del preview.**
`duration:SetFont(STANDARD_TEXT_FONT, 7, "OUTLINE")` sin guard de nil; `title:SetPoint("LEFT",
frame.TitleBg, ...)` falla entero si la plantilla no expone `TitleBg` (usar `frame.TitleBg or
frame`); el slider de escala (`SetValueStep(0.01)`) llama `HUD:SetFrameScale(value, true)` ->
`ApplyFrameStyle()` completo sobre los frames reales en cada paso del arrastre (ver H-1). Aplicar en
`OnMouseUp` o con throttle de 0.1 s.

**H-14 [PULIDO] HUD.lua:845-850, 892-900** - `/rapzo hud on` no imprime nada (`SetPart` solo
imprime en OFF); la rama `frames on|off` si. Unificar dentro de `SetPart`.

**H-15 [PULIDO] Codigo muerto y duplicaciones.**
- HUDStyles.lua:629, 681: `display.RapzoQoLUnitIcon` no se crea en ningun archivo.
- HUDStyles.lua:16-17: `STYLE2_EDGE` y `STYLE2_CONTENT` valen 0 y aparecen en 6 sitios;
  `GetStyleAuraRightInset` devuelve 6 para player pero AuraAnchors solo consulta target/focus.
- HUDFixes.lua:139 (`HideNativeUnitCastBars`), ClassResources.lua:382 (`GetClassResourceInfo`):
  sin llamadores.
- HUDPreview.lua:49-52: fallback a `GetSpellTexture` global (retirado en 11.0); `makeDemo(...,
  classFile, isMob)` parametros sin uso.
- ClassResources.lua:141-142: `SetTexture(WHITE)` seguido de `SetColorTexture`, redundante.
- `isSecret`, `safeCall`, `hudFramesActive`, `WHITE_TEXTURE` se redefinen en 4-5 archivos;
  HUD.lua:2 usa `_G.RapzoBags` mientras el resto usa `_G.RapzoQoL or _G.RapzoBags`. Centralizar
  en `HUD.util`.
- Arranque redundante: `PLAYER_ENTERING_WORLD`/`PLAYER_REGEN_ENABLED` se manejan en 5 frames
  distintos (HUD 953-999, HUDFixes 347-364, HUDStyles 796-838, ClassResources 411-436,
  AuraAnchors 218-248) mas timers 0.5/0.6/0.7/2.0 en cada archivo; `PLAYER_TARGET_CHANGED`
  re-estiliza en HUD.lua 961-971 y otra vez en HUDStyles 819-822; `applyAll` corre dos veces por
  `SetPart` (hooks en HUDFixes 383 y 397). Un solo despachador en HUD.lua que llame
  Fixes/Styles/Resources/Anchors en orden reduciria mucho ruido.
- HUD.lua:489-498: `applyDisplayColor` pinta los bordes de health solo en V2; en V1 depende del
  hook de `ApplyFrameStyle` (H-1). Si se arregla H-1, mover el `setEdgesColor` de V1 ahi.

Lo que esta bien en HUD: salud/poder secretos van directo a `SetMinMaxValues/SetValue` y los
textos solo tras `isSecret` (HUD.lua:563-600); reversibilidad con tablas weak-keyed y snapshot en
la primera modificacion (`nativeRegionAlpha`, `nativeCastBarState`, `restArtAlpha`,
`containerState`), restaurando solo si `modified`; AuraAnchors difiere `SetPoint` a
`PLAYER_REGEN_ENABLED` y ancla a `UIParent` con coordenadas absolutas; los hooks comprueban
`hudFramesActive()` y quedan inertes con Unit Frames OFF; las geometrias documentadas en CLAUDE.md
coinciden con las constantes del codigo.

### 2.13 Config (`Config/Config.lua`)

**CF-1 [MEDIO] Config.lua:155, 598 - Listas de modulos incompletas** (ver C-2). Ni
`reflectHerald`, `cooldownPulse`, `combatText` ni `expansionFilters` tienen checkbox en el panel
propio ni en la categoria raiz. Fix: anadir las claves a las tres listas y un checkbox por modulo con
`RB:SetFeatureEnabled` / `CooldownPulse:SetEnabled` / `CombatText:SetEnabled` /
`ExpansionFilters` (CLAUDE.md 8.7 y 8.10 ya lo tenian como pendiente).

**CF-2 [PULIDO] Config.lua:130-138** - `RapzoQoLConfigFrame` no esta en `UISpecialFrames` (ESC no
lo cierra), a diferencia de la pantalla AFK.

**CF-3 [PULIDO] Config.lua:110-127, 637-641, 654-657** - Ramas muertas en 12.x:
`ColorPickerFrame.func/previousValues` (`SetupColorPickerAndShow` existe desde 10.2.5),
`InterfaceOptions_AddCategory`, `InterfaceOptionsFrame_OpenToCategory`. Inofensivas por los guards.

**CF-4 [PULIDO] Config.lua:226-229** - "Tipo + Item ID" escribe `showItemType` y `showItemID` a la
vez; si por slash quedan distintos (`/rapzo tipo off`), el checkbox se ve desmarcado y al marcarlo
enciende ambos.

Lo que esta bien: los setters van por `HUD:SetPart`, `Vendor:SetEnabled`, `AFK:SetEnabled`; ambos
paneles se crean una sola vez y refrescan en `OnShow`; `RegisterCanvasLayoutCategory` +
`RegisterAddOnCategory` + `OpenToCategory(id)` es la secuencia correcta; las subcategorias de
CooldownPulse/CombatText se cuelgan bien de `RB.Config.settingsCategory`; `/rapzo help` si lista
`pulse`, `damage`, `reflect` y `expfilter`.

### 2.14 Documentacion, TOC y release

**D-1 [MEDIO] CLAUDE.md desactualizado respecto al codigo.**
`grep -n 'CooldownPulse\|CombatText\|pulse\|damage' CLAUDE.md` devuelve cero resultados. Faltan:
orden del TOC (seccion 5: van entre ReflectHerald y HUD), modulos registrados (seccion 6:
`cooldownPulse`, `combatText`), arbol de settings (seccion 7: `cooldownPulse` con
`ignored/learned/x/y/minCooldown/iconSize/...`, `combatText`), comandos (seccion 10: `/rapzo pulse
...`, `/rapzo damage ...`, `/rapzo combattext`), inventario (seccion 11), que CombatText usa
LibStub/LSM de forma opcional (seccion 4) y que `combatText` es OFF por defecto. README.md y
LEEME_INSTALACION.txt tampoco los mencionan. La fecha del snapshot (2026-09-03) y "ultimo tag
v3.0.0-alpha3" siguen igual.

**D-2 [BAJO] AGENTS.md** sigue diciendo que el desarrollo va en `feature/afk-screen-alpha5`;
CLAUDE.md dice `main`. Marcar AGENTS.md y CODEX_HANDOFF.md como historicos en su cabecera o
corregir la regla 7.

**D-3 [BAJO] TOC** - Las notas del TOC ya mencionan Cooldown Pulse y Combat Text; correcto.
`AFKBrand.lua` se puede retirar del TOC si se aplica A-2.

**D-4 [PULIDO] release.yml** - Correcto. El ZIP no excluye nada porque solo empaqueta `RapzoQoL/`;
si algun dia se anaden archivos de desarrollo dentro de esa carpeta habra que excluirlos.

---

## 3. Plan de trabajo sugerido (por sesiones)

**Sesion 1 - Inventario y vendedor (sin riesgo de taint, todo probable en juego en 10 min):**
1. V-1 ranuras 11/12 (`frame:Show()` en `LayoutMerchantSlots`).
2. CO-1 housing (`totalNumStored + totalNumPlaced`).
3. V-2 `map()` sin fallback al indice crudo.
4. C-1 personaje fantasma + migracion de claves duplicadas.
5. S-1 guard de `bankOpen` en el escaneo diferido.
6. C-2 / CF-1 listas de modulos y checkboxes que faltan.
Checklist: abrir vendedor con >12 objetos (fila 3 completa), filtro "No obtenidos" con una
decoracion ya comprada, comprar con filtro activo, Compra <-> Recompra, `/rapzo gold` sin
duplicados, abrir/cerrar banco rapido y comprobar que el tooltip sigue mostrando el banco.

**Sesion 2 - Modulos nuevos:**
1. CT-1 foto pristina de CVars + `GetCVarDefault`.
2. CT-2/CT-3 aplicar fuente en `ADDON_LOADED` y validar nombres de CVars/fuentes con `/dump`.
3. P-1 conservar `states` al reescanear; no rescanear en `OnShow` si ya hay catalogo.
4. P-2 cerrar medicion solo con `not active`; ultima duracion en vez de maximo.
5. P-3 holder sin escala para la animacion.
6. P-4 cachear settings/enabled y bajar el poll.
7. D-1 documentar ambos modulos en CLAUDE.md/README/LEEME.

**Sesion 3 - HUD (requiere pruebas con mUI, combate y Edit Mode):**
1. H-1 separar estilo de valores; quitar hooks duplicados.
2. H-2 `RegisterUnitEvent`.
3. H-3 restaurar tipografia/alturas/colores en `applyStyle1`.
4. H-4 castbar V2 secret-safe.
5. A-1/H-5 `C_SpecializationInfo`.
6. H-6/H-7 alinear preview offline e in-game.
Checklist: el de CLAUDE.md seccion 13 "Despues de cambios HUD" completo, mas `/rapzo hud style 2`
-> `style 1` sin `/reload` comparando fuentes y color del power.

**Sesion 4 - Pulido:** el resto de BAJO/PULIDO, borrar AFKBrand.lua, R-1, S-2/S-3/S-4, V-3..V-9.

---

## 4. Cosas que estan bien (para no tocarlas por accidente)

- Regla "rellenar solo nil" respetada en `EnsureDB`; `RapzoBagsDB` intacta.
- Valores secretos: HUD (salud/poder/nivel), AFK (`UnitIsAFK`), ReflectHerald (todo en pcall),
  Tooltip (`data.id`/link), CooldownPulse (`plain()`) siguen la regla; las excepciones estan en
  H-4, C-7 y las dudas de la seccion 5.
- Reversibilidad del HUD con snapshots weak-keyed y restauracion solo si `modified`.
- AuraAnchors difiere `SetPoint` a fuera de combate y ancla a `UIParent`.
- Vendor envuelve exactamente las APIs que Blizzard 12.x usa en `UpdateMerchantInfo`.
- Detectores de Collections (pets, monturas, recetas, sets) con indices correctos para 12.x.
- Config enruta por los setters reales y registra la categoria Blizzard con el API actual.
- El fix `44c985c` de CooldownPulse (`offSpecID == 0`) es correcto.

---

## 5. Dudas que solo se pueden cerrar dentro de WoW 12.1

Comandos utiles: `/dump GetCVar("WorldTextGravity")`, `/dump C_CVar.GetCVarInfo("WorldTextScale_v2")`,
`/dump CombatTextFont, DamageNumberFont, WorldFont`, `/dump C_Spell.GetSpellCooldown(ID)`,
`/dump C_Container.GetContainerNumSlots(6)` con el banco cerrado, `/dump GetSpecialization`.

1. Si `C_Container.GetContainerNumSlots(CharacterBankTab_N / AccountBankTab_N)` devuelve > 0 con el
   banco cerrado (gravedad real de S-1) y si `Characterbanktab = -2` / `Accountbanktab = -3`
   devuelven slots (posible doble conteo en `GetBankIndexes`, que los incluye por nombre).
2. Si `SpellCooldownInfo.isActive` / `isOnGCD` existen y son NeverSecret (todo CooldownPulse
   depende de ello).
3. Si el motor lee `DAMAGE_TEXT_FONT` a tiempo desde `PLAYER_LOGIN`, y si `WorldTextGravity`,
   `WorldTextRampDuration`, `*_v2`, `DamageNumberFont` y `WorldFont` existen.
4. Si `SendChatMessage` a PARTY/INSTANCE_CHAT desde un handler de evento esta permitido en
   contenido restringido (ReflectHerald anuncio de grupo).
5. Si `GetSpecialization`, `GetSpecializationInfo` y `GetCoinTextureString` siguen presentes.
6. Si modificar las tablas de filtros de la AH/pedidos mancha una ruta protegida (E-2).
7. Semantica exacta de `==` contra un valor secreto (H-4): error o `false`.
8. Firma real de `CreateFrame("AuraContainer", ..., "CustomAuraContainerTemplate")`,
   `AddAuraGroup`, `SetApplicationCount`, `UpdateAllAuras`; si un AuraContainer de addon es frame
   protegido; existencia de `UnitCastingDuration`/`UnitChannelDuration` y
   `StatusBar:SetTimerDuration`; si `TargetFrameMixin.UpdateAuras` y `GetAuraContainer()` siguen
   tras el refactor de auras de 12.x; si `PlayerFrame_UpdateStatus` sigue siendo global; si
   `"Textures\\MinimapMask"` es la mascara por defecto; si Edit Mode fuerza `SetAlpha(1)` en las
   castbars nativas.
9. Si en contenido restringido `ContainerItemInfo.stackCount`/`itemID` o `line.leftText` de
   `C_TooltipInfo` llegan secretos: `count <= 0` en Scanner.lua:13 y `line.leftText ==
   ITEM_SPELL_KNOWN` en Collections.lua:17 no tienen guard.
10. Si el panel de CombatText se recorta en el canvas de Settings (CT-4).
11. El conflicto de taint con mUI (`FocusFrameSpellBar:SetPoint()`) sigue sin validarse en juego,
    como ya indica CLAUDE.md seccion 9.6.

---

## 6. Alcance y metodo

- Lectura completa de los 19 archivos Lua, el TOC, `preview/index.html`, `release.yml` y los
  cuatro documentos (`CLAUDE.md`, `README.md`, `LEEME_INSTALACION.txt`, `AGENTS.md`,
  `CODEX_HANDOFF.md`).
- Contraste contra el codigo publico de Blizzard 12.x para: `MerchantFrame.lua`
  (`UpdateMerchantInfo`, `UpdateBuybackInfo`), `BagIndexConstantsDocumentation.lua`,
  `HousingCatalogUIDocumentation.lua`, `TooltipInfoSharedDocumentation.lua`,
  `BankDocumentation.lua`, `TransmogDocumentation.lua`, `ItemConstantsDocumentation.lua`.
- No se ejecuto nada dentro de WoW; no existe suite automatizada. Todo lo marcado como DUDA queda
  para la validacion en juego de Rapzo.
- Este informe vive en la rama `claude/addon-review-complete-k37k2z`. CLAUDE.md ya se actualizo
  (secciones 5, 6, 7, 8.11, 8.12, 9, 10, 11, 12).

---

## 7. Estado de los hallazgos tras aplicar los fixes

### Resueltos (commit entre parentesis)

- Core: C-1 (clave normalizada + `RB:MigrateCharacterKeys`), C-2, C-3, C-4, C-5 (reset recarga
  la UI), C-7 (`a91b68e`). C-6 y C-8 documentados, sin cambio.
- Scanner: S-1, S-2, S-3, S-4, S-5 (`a91b68e`). S-6 documentado.
- Search: SE-2, SE-3, SE-4 (`a91b68e`). SE-1 (coste por busqueda) pendiente: requiere
  reestructurar `GetMatches`; no bloquea nada.
- Collections: CO-1, CO-2, CO-3, CO-4 (`a91b68e`).
- Vendor: V-1, V-2, V-3, V-4, V-5, V-6, V-7, V-9, V-10 parcial (`a91b68e`). V-8 (`showOwnedCount`
  sin comando) pendiente, trivial.
- ExpansionFilters: E-1, E-3 pendientes (pulido); E-2 es duda de juego.
- AFK: A-1, A-2 (AFKBrand.lua borrado), A-3 (`a91b68e`).
- ReflectHerald: R-1 (`a91b68e`); R-2 duda de juego.
- Cooldown Pulse: P-1, P-3, P-4, P-5, P-6, P-7 (`f2b5555`). P-2: se guarda la ULTIMA duracion
  medida (no el maximo); el cierre por GCD se mantiene a proposito (ver nota en CLAUDE.md 8.11);
  las cargas siguen sin tratarse por separado (`GetSpellCharges` puede ser secreto en combate).
- Combat Text: CT-1, CT-2, CT-3, CT-4 (panel compacto), CT-5 documentado (`f2b5555`).
- HUD: H-1, H-2, H-3, H-4, H-5, H-6, H-7, H-8, H-10, H-11, H-12, H-13, H-14 y parte de H-15
  (RapzoQoLUnitIcon, HideNativeUnitCastBars, GetClassResourceInfo, GetSpellTexture) (`7c1be20`).
  H-9 (mascara del minimapa) pendiente: no se puede verificar offline que textura restaura la
  forma redonda; sigue necesitando `/reload`. El resto de H-15 (helpers duplicados, despachador
  unico de eventos) queda como refactor opcional.
- Config: CF-1 (`a91b68e`). CF-2, CF-3, CF-4 pendientes (pulido).
- Tooltip: T-1..T-4 pendientes (pulido/duda).
- Docs: D-1 y D-3 resueltos; D-2 (AGENTS.md) marcado como historico.

### Validar en juego (en este orden)

1. Vendedor con mas de 12 objetos: la fila 3 de la grilla 4x5 debe estar completa. Filtro
   "No obtenidos" y comprar con el filtro activo. Compra <-> Recompra varias veces. Apagar Vendor
   y comprobar que el tooltip nativo vuelve sin `/reload`.
2. Una decoracion de housing ya comprada debe salir OBTENIDO (en verde, sin el check).
3. `/rapzo gold`: un solo Rapzo por reino. Si habia fantasma, la migracion lo fusiona al login.
4. Abrir el banco, mover un objeto y cerrar inmediatamente: el tooltip sigue mostrando el banco.
5. `/rapzo hud style 2` -> `style 1`: fuentes, alto del nombre y color del power de V1 intactos.
   Target/Focus con casts, auras y combate; Edit Mode; con mUI.
6. Cooldown Pulse: usar un CD largo, cruzar una pantalla de carga y comprobar que avisa al
   terminar. `/rapzo pulse list` con la duracion aprendida.
7. `/rapzo damage status`: cuantos CVars/objetos de fuente existen realmente. Activar, cambiar
   escala, desactivar: el texto de mundo debe volver al tamano de Blizzard.
8. Ambos paneles de Config: los diez modulos en el estado y los cuatro checkboxes nuevos.

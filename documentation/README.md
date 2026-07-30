# Terry the Egg — vertical slice

Prototipo 2D para Godot 4.x, escrito íntegramente en GDScript. Usa una única pantalla lógica de 320 × 288, escalado entero y filtro nearest. No usa IA, entrada de texto libre, cámara, micrófono, red ni archivos ajenos al guardado del juego.

## Ejecutar

1. Abre `project.godot` con Godot 4.x.
2. Pulsa **F6/F5** o el botón de ejecutar proyecto.
3. Para las pruebas automatizadas:

   `godot --headless --path . --script tests/test_runner.gd`

La escena principal es `res://scenes/main/main.tscn`.

## Controles

- Ratón sobre huevo/criatura: cursor de mano.
- Mantener clic izquierdo y mover de lado a lado sobre un huevo: frotar.
- Mantener clic izquierdo y recorrer una distancia corta sobre una criatura: acariciar.
- **Comer**: une nutriente al cursor durante incubación y comida después; suéltalo sobre el objetivo.
- **Jugar**, **Dormir** o **Estado**: selecciona la acción y pulsa una criatura.
- **Limpiar**: selecciona la herramienta y pulsa una suciedad concreta.
- Clic derecho: cancela la herramienta.
- **F3** o **Ctrl+D**: muestra/oculta el panel de depuración.

Terry necesita una caricia válida antes de cada sueño.

## Flujo narrativo

La fase de incubación termina al abrir los tres huevos. La convivencia se completa al alimentar dos veces a cada criatura, jugar una vez con cada una, acariciar dos veces a Terry, hacerla dormir, limpiar una suciedad y acumular 20 segundos de cuidado activo.

Al quedar lista la desaparición, Pipa desaparece al terminar un sueño de Terry o al abrir de nuevo el juego. El evento queda guardado inmediatamente. Terry inicia después el diálogo «Se fue.» con tres respuestas cerradas.

Al finalizar ese diálogo se toma una fotografía de los contadores. Desde ese punto deben realizarse con Terry cinco comidas, cinco juegos y diez limpiezas. `RequirementPromptSystem` elige símbolos a partir de lo que falte, con prioridad: necesidad crítica, requisito narrativo, necesidad normal y personalidad. El diálogo 2 desbloquea **Enseñarle tu lado**, un fundido a negro local sin acceso a dispositivos.

## Datos y extensibilidad

- `data/creatures/creatures.json`: nombres, colores, siluetas, personalidad, deterioro y reglas especiales.
- `data/phases/phases.json`: fases, acciones disponibles y requisitos reutilizables.
- `data/dialogues/dialogues.json`: nodos, opciones cerradas, respuestas y enlaces.
- `data/requirements/post_dialogue.json`: forma documental del conjunto de requisitos post-diálogo.
- `data/actions/actions.json`: etiquetas y símbolos de acciones.

Para añadir una criatura, agrega su definición y estado inicial en `TerryGameState.CREATURE_IDS`, así como una posición en la escena principal. Para añadir un diálogo, crea una entrada con `start` y `nodes`; cada opción tiene un valor persistente y un `next`. Para crear una fase, agrega un objeto a `phases.json` y usa los tipos de requisito ya soportados por `ProgressionDirector`.

## Arquitectura

- `TerryGameState`: estado serializable, necesidades, contadores, flags, respuestas y desbloqueos.
- `CreatureDefinition`, `CreatureController`, `NeedSystem`: datos, interacción visual y deterioro.
- `EggController`: calor, gesto con inversión de dirección, grietas y nacimiento.
- `CursorManager`, `ItemDragController`: cursores centralizados, herramienta y validación de drop.
- `SymbolBubble`: prioridad, duración, persistencia y secuencias de símbolos.
- `ProgressionDirector`, `RequirementPromptSystem`: fases por datos y peticiones antbloqueo.
- `DialogueManager`: árboles totalmente escritos y respuestas cerradas.
- `SaveManager`: JSON persistente y deterioro offline limitado.
- `AudioManager`: pitidos no verbales generados localmente.

## Guardado

El archivo se escribe en `user://terry_the_egg_save.json`. En Windows suele corresponder a `%APPDATA%/Godot/app_userdata/Terry the Egg/terry_the_egg_save.json`. El panel de depuración permite guardar, cargar o borrar únicamente este archivo.

## Sprites y animaciones

Los placeholders actuales se dibujan en `EggController` y `CreatureController`, de modo que no requieren assets externos. Para sustituirlos:

- fotogramas recomendados: 32 × 32 o 48 × 48 píxeles;
- convención: `<creature_id>_<animation>_<frame>.png`;
- 2–4 fotogramas por animación;
- 4–8 FPS, con nearest y sin mipmaps;
- reúne los fotogramas en `SpriteFrames`, añade un `AnimatedSprite2D` al controlador y conserva los nombres de estado (`idle`, `eat`, `happy`, `sleep`, `play`, `pet_reaction`, `talk`, etc.);
- para una animación nueva, añade el nombre al recurso visual y haz que `react()` lo seleccione; la lógica de necesidades no cambia.

## Limitaciones deliberadas

El prototipo usa animación procedural de pocos estados, pitidos sintetizados y una sola comida genérica. La suciedad se distribuye alrededor de las criaturas sin navegación. No hay minijuego: jugar es una reacción corta preparada para reemplazarse. El panel de depuración prioriza controles compactos y edición explícita por botones; no es una herramienta final para diseñadores.

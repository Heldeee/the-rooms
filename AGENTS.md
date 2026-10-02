# TheRooms — contexte de développement

Jeu 3D à la première personne centré sur l'exploration des Backrooms : espaces liminaux, désorientation, ambiance sonore et éclairage fluorescent. Préserver cette direction ; les combats, monstres et mécaniques de survie ne sont pas des exigences établies.

**Direction utilisateur : Kane Parsons / Backrooms found footage, admiration du chaos et de la beauté des espaces.** Lire `DIRECTION_ARTISTIQUE.md` pour le prompt de conception, les biomes cohérents, la verticalité et les anomalies progressives. Les échos sont des répétitions spatiales d'objets, comme sur la référence utilisateur.

## Environnement vérifié le 1 octobre 2026

- Windows, PowerShell, GDScript. L'éditeur utilisateur et `project.godot` sont désormais en **4.7.2 stable / Forward Plus**. Préserver cette version choisie par l'utilisateur. L'ancien 4.4.1 reste installé et le MCP HTTP le sélectionne encore : vérifier le moteur réellement lancé.
- Racine du jeu : `.`.
- Moteur actif : `Godot 4.7.2 installé localement`.
- Serveur MCP local : `godot-mcp/dist/index.js`, lancé par Node.js.
- Les skills mentionnant uniquement 4.4.1 sont antérieurs à ce changement. Vérifier les API et le rendu avec le moteur réellement utilisé.

## Carte du projet

- `scenes/main.tscn` : scène principale, instance de `scenes/player/player.tscn`, environnement, génération et ambiance.
- `scripts/player.gd` : CharacterBody3D, déplacement à 4 m/s, gravité, regard souris et head bob ; aucun sprint (choix utilisateur), action `jump` dédiée.
- `scripts/room_generator.gd` : mosaïque du niveau 0 générée progressivement. Métadonnées conservées, géométrie chargée à 30 m, préparée à 38 m et déchargée au-delà de 46 m. Les passages restent fermés vers une salle non chargée. Les scènes de `scenes/rooms/` sont des ressources anciennes, non utilisées par ce pipeline.
- `scripts/audio_manager.gd`, `ambient_shift.gd`, `light_flicker.gd`, `pause_menu.gd` : ambiance et interface ; lire leurs contrats avant modification.
- `props/`, `textures/` : ressources existantes à réutiliser.
- `addons/godot_mcp/mcp_bridge.gd` et autoload `MCPBridge` : contrôle du jeu lancé, inactif sans port configuré, écoute sur localhost.

## Streaming et performance — 30 septembre 2026

- Configuration active : graine 3, `max_rooms = 0` (pas de limite fixe au plan). La construction est atomique, au plus une salle par frame. Ne pas ouvrir une connexion avant que les deux coques soient chargées.
- Sols, murs, plafond, grilles et mobilier regroupés en MultiMesh par matériau. Murs avec occluders ; sources fluorescentes espacées d'environ 4,5 m, sans ombres. SDFGI et SSAO désactivés pour la fluidité ; Forward Plus conservé.
- Décoration déterministe par empreinte ; couloirs périphériques et croix centrale réservés pour la capsule. Mobilier rare : bureaux, chaises, classeurs. Préserver le caractère largement vide du niveau 0.
- Audio : 8 variantes PCM de pas amortis sur moquette, cadence selon distance réellement parcourue, pas uniquement au sol. Maximum 8 lecteurs, dont un bourdonnement très discret attaché à un fluorescent de la salle courante. Aucun événement aléatoire sans source. Le menu suspend réellement l'arbre et coupe les bus ; le bridge traite les commandes pendant la pause.
- Découvertes uniques, progression sur 60 salles ; revisites et rechargements ne comptent pas deux fois. Régénération replace le joueur au spawn et réinitialise les découvertes.
- `tests/streaming_validation.gd` : pause, audio, connexité, dégagements, portes chargées/non chargées, rayons de fermeture et graines 3/7/19/42/101. `tests/streaming_walk.gd` : parcours avec collisions à 4 m/s et mesures de temps de frame réels.
- `get_stream_stats()` expose plan, salles chargées, file, découvertes, lumières et coûts de construction. Les métadonnées augmentent avec l'exploration ; leur persistance ne constitue pas une sauvegarde disque.
- Le MCP HTTP local utilisateur est `http://127.0.0.1:7878/mcp`, avec outils `godot_run`, `godot_eval`, `godot_screenshot`, `godot_stop`. Il possède un état distinct des anciens outils MCP stdio.

- pour lancer le serveur mcp, faire ceci:

```powershell
$env:GODOT_BIN = "CHEMIN_VERS_GODOT_4_7_2"
$env:GODOT_PROJECT_ROOT = "CHEMIN_VERS_THEROOMS"
$env:GODOT_MCP_ADVANCED = "0"
node ./dist/index.js --transport http --host 127.0.0.1 --port 7878
```

## Méthode

Lire les scripts, ressources et chemins de nœuds concernés. Faire une modification ciblée, préserver les UID, ressources et changements existants. Ne pas éditer `.godot/` ou reconstruire les scènes entières pour un petit ajustement. Sauvegarder avant de remplacer un fichier existant.

Utiliser les skills `godot-project-workflow`, `backrooms-level-design` et `godot-mcp-diagnostics` selon la tâche. Les changements FPS exigent une vérification des collisions, du regard et de la pause ; les changements de génération exigent une graine fixe et une vérification de la connectivité et du passage du joueur.

Valider avec le moteur actif 4.7.2 local : import headless, puis démarrage court et logs. L'absence d'erreur de parsing ne prouve pas la qualité visuelle ou le comportement interactif. Signaler précisément les contrôles réalisés et leurs limites.

## Passe visuelle et sonore — 1 octobre 2026

- Bloom désactivé dans la scène ET AmbientShift ; aucune réactivation à la découverte de salles. Résolution 3D native, TAA/FXAA désactivés, MSAA 2x, filtrage anisotrope 8x. Ne pas présenter un rendu avec une qualité différente du jeu comme une capture du jeu.
- `shaders/level0_wall.gdshader` : papier peint en coordonnées monde, grain, lés, petits motifs et usure organique ; lignes atténuées selon l'empreinte du pixel pour éviter le moiré. `level0_carpet.gdshader` : fibres et variations de pile/stains, sans larges stries floues. Bruit partagé et matériaux mis en cache par palette.
- Six palettes coordonnent murs, moquette, plafond et température des fluorescents. Grandes salles jusqu'à 20 × 15 m, alcôves basses, colonnes, partitions, bancs, étagères, bureaux avec CRT. Dimensions suffisantes pour placer les props sans obstruer la croix et les chemins périphériques.
- Plinthes de 28 mm sur la face intérieure des murs : aucune traversée du plan partagé, extrémités raccourcies aux angles. Linteaux occasionnels au-dessus des passages, toujours assez hauts pour la capsule.
- `tests/art_capture.gd` : captures directes du framebuffer et export des variantes de pas. `RAPPORT_LEVEL0_2026-10-01.md` détaille résultats, réglages et limites.

## Biomes, verticalité et chaos — seconde passe du 1 octobre 2026

- `scripts/level0_profile.gd` : territoires de Voronoï d'environ 48 m, frontières de 14 m, palettes proches interpolées ; familles de salles selon le biome. Rien ne dépend d'un nouveau tirage lors des revisites.
- Terrain continu et déterministe : paliers de 1,5 m / 1 m reliés par des rampes de 5 m. `get_floor_height(point)` remplace toute hypothèse d'un sol mondial à zéro. Sols en ArrayMesh avec collision concave ; taille des mailles 1,25 m alignée sur les cassures du profil.
- Les plafonds sont au-dessus du point le plus haut de la salle ; les linteaux se ferment au-dessus de l'ouverture commune. La coque extérieure reste complète même quand les cloisons intérieures sont volontairement incomplètes.
- Chaos croissant avec la distance spatiale au départ, début à 65 m, maximum à 240 m. Quatre anomalies persistantes : `quarter_turn`, `partial_walls`, `embedded_props`, `echo`. Retourner au départ ne déforme pas les anciennes salles.
- La salle à 90° tourne l'architecture : ancienne paroi sous les pieds, plafond/grille/néons sur une paroi verticale, mobilier tourné. La gravité et le contrôleur restent orientés dans le monde ; ce n'est pas une transition avec gravité locale variable.
- Les props encastrés restent près des coins pour ne bloquer ni les portes actuelles ni celles ajoutées par une boucle ultérieure. Les échos sont des panneaux solides répétés ; aucune traînée ajoutée à tout l'écran.
- `scripts/footstep_audio.gd` : banque de huit contacts fortement filtrés, deux AudioStreamPlayer réutilisés, volume à -24 dB, aucune réverbération de pas. Le bourdonnement des luminaires est réduit à -48 dB. Les sons restent procéduraux en l'absence d'enregistrements locaux adaptés.
- Confort visuel : MSAA 4x, TAA activé, interpolation physique, bob de caméra réduit de 0,08 à 0,025 m ; motifs du papier peint filtrés selon l'empreinte du pixel. Le TAA peut légèrement adoucir l'image en mouvement, à vérifier avec le retour utilisateur.
- Tests : profil/biomes/pentes, cinq graines, passages à la hauteur du terrain, captures d'anomalies naturelles après parcours profond. `streaming_walk.gd -- --deep` prépare un départ éloigné avant de mesurer un parcours avec collisions à 4 m/s.

Utiliser les outils MCP disponibles pour inspecter, lancer et contrôler le projet. Le préfixe actuel `mcp__playwright__` expose des outils Godot ; choisir d'après la description de l'outil. Un serveur accessible ne garantit pas que son moteur ou son bridge fonctionne.

Répondre en français, avec le résultat, les fichiers modifiés, la validation et les problèmes restants. Les notes privées globales ne sont à modifier que lors d'une demande de notes ou d'enseignement.

## Passe escaliers et ouvertures — 2026-10-01
- Terrain borné 0–2,5 m : longs paliers, escaliers visibles sur X, rampes rares sur Z ; collision de support continue pour éviter le jitter. Ne pas réintroduire un cumul d'altitude illimité.
- Profils de salle : base au minimum du terrain échantillonné, plafond au maximum + hauteur ; important pour fermer les murs sur les descentes.
- Connections : `opening` partagé et stable, arche segmentée ou passage large jusqu'au plafond commun.
- Salles quarter_turn : aucune grille verticale ni chaise imposée.
- `_equipment` : distributeur, casier ventilé, CRT sur chariot, desserte ; remplacement de l'ancien cube encastré, diversification archive/service.
- Validation : streaming_validation zéro échec, montée/descente dans stairs_validation, marche rendue p95 1,939 ms, pic 6,495 ms (RTX 4070 SUPER). Rapport : RAPPORT_ESCALIERS_OUVERTURES_PROPS_2026-10-01.md.

## Correction de direction — pentes conservées, 2026-10-01
La clarification utilisateur remplace la décision de la passe précédente : les dénivelés généraux restent des pentes, sans marches plaquées dessus. Terrain borné et paliers conservés. `_build_floor` utilise le même ArrayMesh pour rendu et collision ; `stairs_at` supprimé. `tests/ramps_validation.gd` remplace le test d'escaliers et vérifie montée/descente des rampes. Les véritables escaliers sont réservés à la desserte d'un espace surélevé distinct ; aucune mezzanine ni liaison entre étages n'est encore implémentée.
Les backups sont exclus de l'import Godot via `backups/.gdignore` pour éviter que leurs copies GDScript dupliquent les classes globales.

## Nettoyage du dépôt — 2 octobre 2026
- Dépôt Git existant conservé, historique non réécrit. README avec cinq captures réelles dans docs/screenshots.
- Anciens props, scènes scenes/rooms, textures inutilisées, CLAUDE.MD et backups archivés hors dépôt dans ../local-archive-20261002. Le jeu actif ne dépend pas de ces ressources.
- `.gitignore` exclut caches, réglages personnels, logs et sauvegardes. Les fichiers `.import` des assets actifs restent versionnés : ils contiennent les réglages d'import Godot, pas le cache binaire.
- Import Godot 4.7.2 et streaming_validation exécutés après nettoyage. Aucune publication distante effectuée.

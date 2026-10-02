# Corrections et streaming du niveau 0 — 30 septembre 2026

## Résultat

Les erreurs de lumière, la fuite des lecteurs audio, la fausse pause, le scintillement figé et le comptage des revisites sont corrigés. Le sprint est retiré conformément à la demande. Le niveau s'étend maintenant pendant l'exploration, avec une réserve de salles et des frontières solides vers la géométrie non chargée.

Le rendu a été vérifié avec Godot 4.4.1 Forward Plus sur la **RTX 4070 SUPER locale**. Aucun accès Internet, téléchargement, migration de moteur ou changement de renderer. Les fichiers existants ont été sauvegardés dans `../backups/level0-before-streaming-20260930/` avant remplacement.

## Génération progressive sans ouverture sur le vide

- Le plan se compose de rectangles sans chevauchement sur une grille de 2,5 m. Les panneaux de plafond restent à 0,625 m.
- Une réserve initiale est préparée autour du spawn. Avec la graine 3 : **162 empreintes planifiées et 73 salles construites** au départ. Une empreinte planifiée est une petite fiche de métadonnées, pas une scène complète.
- À mesure que le joueur avance, les empreintes proches sont développées à 38 m ; la géométrie est chargée à 30 m. Les salles au-delà de 46 m sont déchargées, avec hystérésis pour éviter les reconstructions répétées à un seuil.
- Une salle est construite au plus par frame : sols, plafond, collisions et décoration sont présents avant que les murs voisins ouvrent son passage. Aucun `await` ne coupe cette opération atomique.
- Une connexion vers une salle non chargée reste un mur visible avec collision. Décharger une salle referme les passages correspondants, loin du joueur. Ce sont des frontières solides, pas des trous cachés par un brouillard épais.
- Les métadonnées et la graine de décoration restent disponibles pour revenir sur ses pas. Le mobilier et les variantes d'une salle restent identiques après rechargement.
- La recherche des salles proches utilise les cellules occupées autour du joueur ; elle ne reparcourt pas tout l'historique du monde à chaque frame.
- La régénération remet le joueur au spawn, annule sa vitesse et réinitialise les découvertes. Une récupération est également prévue en cas de chute hors carte.

## Performances

### Mesures locales

| Essai | Médiane | 95e percentile | 99e percentile | Pic |
|---|---:|---:|---:|---:|
| Ancienne version au spawn, 1280×720, 600 frames | 0,973 ms | 1,210 ms | 1,500 ms | 18,218 ms |
| Nouvelle version, parcours physique de 25 s à 4 m/s, 1280×720 | **0,579 ms** | **0,761 ms** | **1,069 ms** | **2,880 ms** |
| Nouvelle version au spawn, fenêtre demandée en 1920×1080, viewport réel 1920×1061, 600 frames après échauffement | **0,769 ms** | **0,849 ms** | **1,100 ms** | **1,308 ms** |

Mesures de temps réel entre frames, VSync désactivée uniquement pendant les essais. Les deux versions n'ont pas le même layout : ces chiffres décrivent les conditions testées, pas une comparaison GPU strictement identique ni une garantie pour toute résolution. L'ancien essai comprend le bug de lumière de l'état audité.

Pendant le parcours final : 162 → **317 salles planifiées**, **112 salles chargées** en fin de parcours, 52 lumières actives à ce point, **63 draw calls** dans la vue finale. La construction atomique la plus lente atteint **1,18 ms**, sous la cible de 2 ms. Huit découvertes ont été comptabilisées ; la neuvième salle cible du parcours était encore en cours d'approche.

Le budget de 60 FPS est de 16,67 ms par frame ; aucun pic mesuré pendant ce parcours n'approche cette limite. Les résultats ne couvrent pas une session de plusieurs heures ni la 4K.

### Réductions de coût

- Grilles du plafond, murs, sols et meubles regroupés en **MultiMesh par matériau**, avec un BoxMesh partagé. Les barres ne produisent plus chacune un nœud et un draw call.
- Matériaux partagés et textures existantes à coordonnées mondiales. La moquette n'est plus régénérée sur le thread principal ; la non-périodicité du précédent calcul runtime disparaît avec ce pipeline.
- Sources fluorescentes espacées d'environ 4,5 m ; panneaux émissifs regroupés ; lumières locales sans ombres. Seul un luminaire par salle peut scintiller.
- Extinction des lumières éloignées et arrêt de leur traitement ; suppression de l'API `enabled` invalide.
- Occlusion par les murs pour éviter de dessiner les salles masquées. SDFGI et SSAO désactivés ; ambiance lisible maintenue par un éclairage ambiant peu coûteux. Forward Plus conservé.
- Sons PCM finis calculés une seule fois au démarrage et réutilisés. Maximum de huit voix, libérées automatiquement à la fin.

Le compromis visuel est explicite : moins d'éclairage indirect dynamique et pas d'ombres projetées par chaque lampe, en échange d'une scène plus légère. Les captures montrent que les espaces restent lisibles et jaunes.

## Salles et mobilier du niveau 0

La majorité des salles reste vide. La diversité repose sur les proportions, les connexions décalées, les couloirs longs, les grandes salles, les colonnes répétées et les cloisons décentrées, avec plusieurs teintes proches de papier peint jaune.

Les zones occasionnellement meublées utilisent maintenant :

- bureaux avec plateau, pieds métalliques, caisson, poignées et feuilles ;
- chaises avec assise, dossier et pieds, orientées vers l'intérieur ou vers le bureau ;
- classeurs avec façades de tiroirs et poignées.

Ces meubles sont des assemblages de géométrie simple regroupée, pour limiter le coût. Les salles meublées ont une taille suffisante pour accueillir leurs props. Deux ensembles au maximum sont placés par salle ; les cubes dispersés de type entrepôt ont été remplacés.

Une allée périphérique de 1,65 m et une croix centrale de 1,8 m sont réservées. Les objets évitent ces zones ainsi que les volumes des autres objets. Les positions et rotations de collision suivent la géométrie visible.

## Autres corrections

- Pause réelle de l'arbre, menu centré, souris libérée et reprise fonctionnelle. Escape ne réagit plus aux répétitions clavier. « Quitter le jeu » correspond à l'action réelle du bouton.
- Le menu configure le **nœud MCPBridge en traitement permanent**, afin de conserver les captures et commandes pendant la pause. Le serveur HTTP réinstalle son bridge au lancement ; le réglage de l'instance évite de dépendre d'une modification écrasée du fichier addon.
- Scène joueur unique, instanciée depuis `scenes/player/player.tscn`. Sprint supprimé ; saut dédié à l'action `jump` ; freinage exprimé par seconde.
- Head bob et pas basés sur le déplacement réel ; pas interrompus en l'air. Hauteur de caméra au repos conservée.
- Compteur de salles découvertes uniques et ambiance calibrée sur 60 découvertes. Le niveau 0 garde un éclairage chaud, y compris lors de la progression.
- Scintillement alimenté par le temps et la vitesse, événements aléatoires exprimés par seconde, interpolation indépendante du framerate.
- Réverbération de salle appliquée aux effets et événements ambiants spatialisés.
- Deux UID de plafond corrigés dans les anciennes scènes, qui restent hors du pipeline actif.

## Validation

**Tests automatisés :** `tests/streaming_validation.gd`, résultat **zéro échec**.

- Graines 3, 7, 19, 42 et 101 : connexité du graphe, reproductibilité après régénération, capsules libres aux ouvertures chargées, ouvertures fermées vers une salle déchargée, dégagement des allées et rayons rencontrant une paroi.
- Quarante transitions de salles en test de charge : le plan augmente jusqu'à environ 619 salles ; la géométrie éloignée est déchargée. Ce test utilise des repositionnements rapides et vérifie le streaming, pas le ressenti d'une marche normale.
- Pause : aucune variation de position, répétition d'Escape ignorée, reprise de l'arbre.
- Audio : limites de voix respectées, lecteurs de pas et d'ambiance libérés après leur durée, aucun pas en l'air.
- Scintillement : temps qui avance pour une lampe visible et traitement arrêté après culling.
- Revisites : aucune découverte comptée deux fois ; régénération remet le compteur à zéro.

**Dans le jeu avec rendu et MCP HTTP :** capture du spawn, du mobilier et du menu ; contrôle souris/yaw, saut, pause et reprise. Les commandes MCP et les captures fonctionnent pendant la pause. Parcours de 25 s avec collisions réelles, sans blocage de navigation ni erreur GDScript dans les logs.

**Import et lancement court :** moteur 4.4.1 exact, import headless puis démarrage sur 120 frames ; aucune erreur de parsing ou de gameplay. `git diff --check` passe.

Les messages Windows de lecture du magasin de certificats et de sauvegarde des préférences de l'éditeur hors workspace restent présents dans les essais headless. Ils sont distincts des scripts du jeu. Aucun problème réseau externe n'a été recherché, puisque le travail reste local.

## Fichiers et limites

Fichiers de gameplay modifiés : les six scripts de `scripts/`, `project.godot`, `scenes/main.tscn`, `scenes/player/player.tscn`, et les deux références de texture dans `room_clutter.tscn` / `room_storage.tscn`. Ajout des deux scripts de validation et mise à jour du contexte dans `AGENTS.md`. Les modifications utilisateur préexistantes sont conservées ; aucun commit n'a été créé.

Captures et journaux se trouvent dans le dossier parent : `level0-furniture.png`, `level0-walk.png`, `level0-pause.png`, `stream-tests.log`, `stream-walk.log`, `stream-render.log`, `stream-runtime.log`, `stream-import.log`. L'état original utilisé pour la comparaison est conservé dans `../backups/perf-baseline/`.

Les salles visibles et les collisions sont présentes avant leur ouverture ; aucune ouverture sur une salle non chargée n'a été détectée. Le streaming n'est pas une sauvegarde sur disque et son historique de métadonnées augmente avec l'exploration. La qualité sonore a été validée par la durée de vie des flux, mais pas par une écoute humaine. Export Windows et longues sessions restent à tester séparément.

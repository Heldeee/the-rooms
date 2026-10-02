# TheRooms : biomes, verticalité, chaos et confort

Cette seconde passe répond aux remarques sur le son, le scintillement en mouvement et les changements d'ambiance trop abrupts. Les fichiers existants ont été sauvegardés dans `../backups/level0-before-biomes-chaos-20261001/`. Les modifications antérieures du projet sont conservées.

## Direction artistique

La référence Kane Parsons / Backrooms found footage et le prompt de conception sont ajoutés à `DIRECTION_ARTISTIQUE.md` et aux consignes du projet dans `AGENTS.md`. La passe se base sur les intentions de l'utilisateur et l'image jointe ; la vidéo indiquée n'a pas été consultée et aucune ressource externe n'a été téléchargée.

## Ce qui change

### Sons de pas

La gestion des pas est extraite dans `scripts/footstep_audio.gd`. Deux lecteurs sont réutilisés, sans création de nœud à chaque pas. La banque compte huit contacts différents, avec attaque arrondie, forte réduction des hautes fréquences et enveloppe courte. Le volume des voix passe de -15 à -24 dB, la synthèse est également moins énergique, la variation de pitch reste minime et la réverbération des pas est coupée. La cadence dépend de la distance réellement parcourue au sol ; marcher contre un obstacle ou être en l'air ne déclenche pas de pas.

Le fluorescent passe à -48 dB, contre -37 auparavant. Il reste localisé sur un luminaire de la salle courante, sans événements ambiants aléatoires.

Le composant accepte désormais une banque de WAV enregistrés, exposée par `AudioManager.footstep_recordings`. En leur absence, il utilise la banque procédurale locale. **Le naturel perçu n'est pas garanti par les tests : ces sons restent synthétiques.** Un aperçu de huit pas, au gain du jeu et sans normalisation, est exporté dans `../chaos-soft-footsteps.wav`.

### Mouvement et crénelage

- MSAA 4x et TAA, avec résolution 3D native. Aucun bloom ni flou de mouvement ajouté.
- Interpolation physique activée : le rendu ne se contente plus des positions mises à jour à 60 Hz.
- Balancement de caméra réduit de 8 cm à 2,5 cm.
- Motifs fins du papier peint filtrés selon la taille du pixel, atténués avant qu'ils ne deviennent trop fins.
- Plinthes suivant les rampes, séparées des faces des murs ; grille du plafond légèrement épaissie.

Ces changements traitent plusieurs causes possibles du rendu fatigant. Le TAA peut légèrement adoucir l'image en mouvement : le retour visuel utilisateur reste nécessaire pour juger le compromis entre netteté et stabilité. Les captures seules ne prouvent pas la disparition de tout scintillement.

### Biomes cohérents

`scripts/level0_profile.gd` définit des territoires spatiaux d'environ 48 m, à partir de points déterministes. Une frontière de 14 m mélange des palettes voisines : papier miel, bureaux fanés, moquette ocre, humidité, néons pâles et ivoire ancien. Toutes restent apparentées au niveau 0.

La palette des murs, de la moquette et des luminaires est coordonnée. Les familles de salles sont pondérées selon le territoire : une zone de bureaux favorise bureaux/classeurs/attente, une zone humide favorise alcôves/services, les autres privilégient volumes vides et colonnes. La variété des proportions demeure, mais l'ambiance n'est plus tirée indépendamment à chaque porte.

Les transitions sont calculées dans l'espace et les propriétés sont conservées dans les métadonnées des salles. Revenir sur ses pas ne relance pas un tirage.

### Verticalité praticable

Le terrain possède maintenant une hauteur mondiale réelle. Des paliers de 1,5 m et de 1 m sont reliés par des rampes de 5 m ; leur pente combinée reste inférieure à environ 20°. Le spawn conserve un sol horizontal à zéro.

Les sols sont des maillages avec collision, dont les points de bord coïncident entre salles. Les plafonds sont placés au-dessus du point le plus haut de chaque pièce. Les ouvertures sont dimensionnées à partir de la hauteur des deux salles et de la pente sur toute leur largeur. Le contrôleur suit les descentes avec un snap de sol de 35 cm ; la récupération après chute se réfère à la hauteur du terrain, plutôt qu'à un seuil mondial de -5 m.

Il s'agit d'une première verticalité continue, avec montées/descentes et volumes hauts. **Il n'y a pas encore de salles superposées occupant les mêmes coordonnées X/Z, de mezzanines ni de système d'ascenseurs.**

### Chaos progressif

Les anomalies commencent à apparaître au-delà de 65 m du départ et augmentent jusqu'à 240 m. Cette progression utilise la distance spatiale au départ, pas un compteur cumulant les allers-retours. Les anomalies découvertes sont persistantes.

| Anomalie | Comportement |
|---|---|
| Salle à 90° | Une ancienne paroi porte les pieds, le plafond/grille/fluorescents deviennent verticaux, le sol d'origine devient une paroi et le mobilier est orienté avec l'architecture. Le volume devient plus haut. |
| Murs partiels | Cloisons intérieures arrêtées à la moitié ou aux trois quarts, avec silhouettes coupées et sections incomplètes. |
| Objets encastrés | Objets traversant volontairement le sol et les parois, placés près des coins. Leur placement évite aussi les portes qu'une boucle ultérieure pourrait ouvrir. |
| Écho d'objet | Trois à cinq panneaux répétés, décalés, inclinés et réduits dans l'espace, avec un graphisme commun. Aucun effet de traînée appliqué à tout l'écran. |

La salle à 90° tourne l'architecture ; **la gravité mondiale du joueur ne change pas**. Une transition où la gravité et la caméra basculent autour d'un axe n'est pas implémentée dans cette passe.

Les déformations affectent les éléments intérieurs ; la coque extérieure et les voisins non chargés restent fermés. Le chaos ne découvre pas de vide pendant le streaming. Le sprint reste absent.

## Vérifications

- Import et exécution avec le moteur local **Godot 4.7.2 / Forward Plus**.
- Validation headless et rendue : **0 échec**, graines **3, 7, 19, 42, 101**.
- Tests du profil : territoire commun autour du départ, déterminisme, frontières de couleur progressives, présence de plusieurs biomes, hauteur du spawn et pente des rampes.
- Connexité, génération/rechargement déterministes, coque fermée, passages chargés/non chargés et dégagements contrôlés à la hauteur du terrain. Les requêtes de capsule disposent d'une petite marge au-dessus du sol pour distinguer les obstacles du contact attendu avec une pente.
- Parcours de 40 transitions rapides en profondeur ; cas de meubles bloquant des portes détectés puis corrigés. Les quatre anomalies sont présentes dans les salles naturellement générées, sans forcer leur type pour les captures.
- Pause, reprise, capture souris, regard, limite de pitch et audio contrôlés. Deux lecteurs de pas fixes, aucune allocation de nœud à chaque contact, voix arrêtées après lecture et absence de pas en l'air.

Les captures `../chaos-quarter_turn.png`, `../chaos-partial_walls.png`, `../chaos-embedded_props.png` et `../chaos-echo.png` viennent du framebuffer en 1280 × 720. Les contrôles ont placé la caméra dans des salles naturellement générées à environ 270–358 m du départ, entre -10,5 et -14,5 m d'altitude. Le test n'ajoute pas de décor ni d'éclairage spécifique aux captures.

## Performance en mouvement

RTX 4070 SUPER, fenêtre demandée 1920 × 1080, framebuffer réel **1920 × 1061**. Deux parcours de 25 secondes à 4 m/s, collisions actives, VSync coupée pour mesurer. Première frame GPU et warmup initial exclus ; il ne s'agit donc pas d'une mesure du démarrage à froid.

| Mesure | Depuis le départ | Départ préparé en profondeur |
|---|---:|---:|
| Frames mesurées | 15 297 | 15 246 |
| Médiane | 1,206 ms | 1,211 ms |
| 95e percentile | 2,683 ms | 2,659 ms |
| 99e percentile | 3,125 ms | 3,046 ms |
| Frame maximale | 5,958 ms | 6,610 ms |
| Maximum de construction observé dans le run | 3,815 ms | 4,287 ms |
| Salles chargées en fin de parcours | 115 | 97 |
| Lumières actives en fin de parcours | 34 | 39 |

Le parcours profond commence à environ 113 m du spawn, dans une salle d'écho, puis poursuit la génération. Aucun blocage rencontré dans ces deux trajets. La verticalité est parcourue avec collisions, pas seulement représentée dans une capture.

La validation qui téléporte rapidement le joueur, construit plusieurs salles pour forcer les cas et change de graine n'est pas le benchmark de marche : ses constructions ont ponctuellement atteint environ 11 ms. Les mesures du tableau viennent des parcours à vitesse normale. Elles ne garantissent pas tous les chemins ou les performances d'un autre GPU.

## Limites observées

- Le premier rendu à froid a comporté une pause de compilation/initialisation de l'ordre de 3,65 s dans un contrôle. Les parcours mesurés ci-dessus excluent explicitement ce chargement initial ; cette pause n'est pas présentée comme corrigée.
- L'environnement de validation restreint ne peut pas enregistrer le cache de shaders ni certains paramètres dans AppData et affiche un accès impossible au magasin de certificats Windows. Le rendu fonctionne, mais ces messages restent dans les logs.
- Deux références `AudioStreamWAV` / `AudioStreamPlaybackWAV` sont encore signalées à l'arrêt de certains tests headless, associées au bus Ambient. Les lecteurs restent bornés pendant le jeu ; le nettoyage final côté serveur audio reste à résoudre.
- Les sons de pas et les props restent des ressources locales procédurales. La fidélité sonore finale nécessiterait des enregistrements adaptés ; le mobilier reste construit avec des primitives.
- Le serveur MCP HTTP de la session conserve son ancien choix de moteur. Les validations ont utilisé directement le binaire 4.7.2 installé, sans modifier sa configuration globale.

## Fichiers principaux

`scripts/level0_profile.gd`, `scripts/footstep_audio.gd`, `scripts/room_generator.gd`, `scripts/audio_manager.gd`, `scripts/player.gd`, `shaders/level0_wall.gdshader`, `shaders/level0_carpet.gdshader`, `project.godot`, `tests/streaming_validation.gd`, `tests/streaming_walk.gd`, `tests/art_capture.gd`, `DIRECTION_ARTISTIQUE.md`, `AGENTS.md`.

# Niveau 0 : passe visuelle et sonore du 1 octobre 2026

Les corrections sont appliquées au générateur actif. Cette passe conserve le streaming, les collisions et la marche sans sprint. Les fichiers remplacés ont été sauvegardés dans `../backups/level0-art-before-20261001/`.

## Constats et corrections

| Remarque | Cause trouvée | Modification |
|---|---|---|
| Voile lumineux, lumière excessive | Bloom à 0,8 puis jusqu'à 1,5 dans AmbientShift, intensité 1,2 ; la scène et le script avaient des réglages différents. | Bloom coupé dans les deux endroits. Fluorescents à 0,6 au lieu de 0,85, émission des panneaux à 0,65 au lieu de 1,8. Remplissage ambiant réduit. |
| Flou et textures peu convaincantes | Cartes de faible définition avec grandes variations floues, faible différenciation des matériaux et filtrage oblique ordinaire. | Papier peint et moquette procéduraux en coordonnées monde : grain, lés, motifs discrets, fibres et usure organique. Filtrage anisotrope 8x, résolution 3D native, MSAA 2x, aucun TAA/FXAA. Les motifs fins s'atténuent à distance pour limiter le moiré. |
| Scintillement des plinthes | Plinthes de 14 cm centrées sur la demi-paroi : chevauchement du plan partagé entre salles. | Profil de 28 mm situé sur la face intérieure, extrémités raccourcies. La face visible est séparée de celle du mur. |
| Tout se ressemble | Quatre nuances très proches ; mobilier limité ; certaines salles trop petites pour placer un seul prop avec les dégagements nécessaires. | Six palettes de murs/sols/plafonds/températures de lumière. Grandes salles jusqu'à 20 × 15 m, colonnes, partitions, alcôves basses, linteaux occasionnels. Tailles minimales adaptées au mobilier. |
| Props trop sommaires | Bureaux, classeurs et chaises uniquement ; couleurs plates. | Bancs rembourrés, étagères avec boîtes, bureaux avec CRT/écran sombre/clavier/support. Grain du bois et du tissu. Placement déterministe, mobilier toujours rare et passages réservés. |
| Pas « papier mâché » | Oscillateur à 75 Hz et bruit blanc, forte variation de pitch et réverbération. | Huit contacts différents mis en cache, bruit filtré grave, talon puis pointe, réverbération SFX réduite à 3,5 %. Cadence fondée sur la distance réellement parcourue ; pas de pas en l'air ou à l'arrêt. |
| Bruits aléatoires sans intérêt | Gouttes, grincements et coups émis autour du joueur sans objet ou lieu associé. | Suppression de ces événements. Une seule source très discrète de fluorescent, placée sur un luminaire réel de la salle courante, avec fondu et atténuation spatiale. Sans luminaire audible, silence. |

## Rendu et version

L'éditeur ouvert et le projet utilisent désormais **Godot 4.7.2**. Le serveur MCP HTTP fourni sélectionne encore **4.4.1**, même avec un argument de version 4.7.2. Le jeu de contrôle lancé par ce serveur a été arrêté ; les validations suivantes ont utilisé directement le binaire 4.7.2 déjà installé. La configuration globale du serveur n'a pas été modifiée.

Les captures `../art-empty.png`, `../art-office.png`, `../art-columns.png`, `../art-alcoves.png`, `../art-service.png` et `../art-lounge.png` proviennent du framebuffer du jeu 4.7.2 en 1280 × 720, sans retouche ni réglage de qualité supplémentaire. Le script déplace le joueur dans des salles générées et fixe son orientation pour les examiner. Il n'ajoute pas de lumière ni de mobilier. Leur apparence statique ne permet pas de conclure à elle seule sur tous les effets visibles en mouvement ou sur une fenêtre intégrée à l'éditeur et redimensionnée.

Réglages effectivement lus dans le viewport : MSAA 2x, TAA désactivé, facteur de résolution 1,0 ; glow désactivé dans l'environnement.

## Validation réalisée

- Import avec le moteur 4.7.2 et chargement des scènes/scripts/shaders.
- Tests en headless puis avec rendu réel : **0 échec**, graines **3, 7, 19, 42, 101**. Connexité, reproductibilité de génération, collision de capsule aux passages, chemins réservés et fermeture des voisins non chargés.
- Déplacements rapides sur 40 transitions pour solliciter chargement/déchargement ; le plan continue à croître et les géométries éloignées sont retirées.
- Pause, reprise, capture souris, regard et borne de pitch contrôlés dans le test rendu.
- Audio : limite de 8 lecteurs, libération des voix de pas, variantes différentes, source positionnée sur un vrai fluorescent, silence lorsque les lumières sont exclues, absence de pas en l'air. Arrêt explicite du son en boucle à la sortie ; aucun avertissement de fuite dans la validation finale.

### Performance du parcours rendu

Godot 4.7.2, Forward Plus, RTX 4070 SUPER, fenêtre demandée 1920 × 1080 ; framebuffer réel **1920 × 1061**, limité par la hauteur disponible de la fenêtre. Parcours automatique à 4 m/s pendant 25 secondes, VSync coupée pour mesurer ; deux premières secondes exclues.

| Mesure | Résultat |
|---|---:|
| Frames mesurées | 25 403 |
| Temps médian | 0,863 ms |
| 95e percentile | 1,247 ms |
| 99e percentile | 1,492 ms |
| Frame maximale | 4,612 ms |
| Construction d'une salle : maximum observé | 1,199 ms |
| Plan / salles chargées en fin de parcours | 298 / 113 |
| Lumières actives en fin de parcours | 56 |
| Draw calls en fin de parcours | 88 |

Aucun blocage rencontré sur ce parcours ; 9 salles découvertes. Ces résultats montrent une marge confortable sur cette machine et ce trajet. Ils ne mesurent pas le démarrage à froid, une exploration de plusieurs heures ni les performances sur un GPU moins puissant. Ils ne constituent pas une comparaison avant/après sous un protocole identique.

## Limites et pistes restantes

- Les pas restent synthétisés localement : leur structure est améliorée et les échantillons `../art-step-0.wav` à `../art-step-7.wav` permettent une écoute, mais les tests automatisés ne prouvent pas le naturel perçu. De vrais enregistrements de chaussures sur moquette seraient l'étape suivante pour une fidélité acoustique supérieure.
- Le mobilier demeure construit avec des primitives légères. Des modèles travaillés et des textures photographiques autorisées pourraient apporter davantage de réalisme ; aucune dépendance ni ressource externe n'a été téléchargée.
- Les ombres dynamiques et la GI coûteuse restent désactivées pour préserver la fluidité. Les petits objets peuvent donc manquer d'ombres de contact.
- Les logs des contrôles affichent un accès impossible au magasin de certificats Windows et, dans les runs rendus, à l'enregistrement du cache de shaders. L'import éditeur ne peut pas non plus enregistrer ses paramètres dans AppData depuis l'environnement restreint. Le moteur charge ses certificats intégrés et les shaders sont rendus ; aucune erreur de parsing ou compilation des shaders n'a été observée. Ces messages d'environnement restent à distinguer des résultats des tests du jeu.
- Un arrêt automatique abrupt avec `--quit-after` signale encore deux références audio à la sortie. La validation qui laisse le serveur audio traiter l'arrêt pendant 100 ms se termine sans cet avertissement. Les lecteurs restent bornés pendant les tests ; le nettoyage lors d'un arrêt abrupt du moteur reste une limite observée.
- Le serveur MCP gagnerait à être relancé avec les chemins du moteur 4.7.2 pour éviter des comparaisons entre deux versions différentes.

Fichiers principaux : `scripts/room_generator.gd`, `scripts/audio_manager.gd`, `scripts/ambient_shift.gd`, `shaders/level0_wall.gdshader`, `shaders/level0_carpet.gdshader`, `scenes/main.tscn`, `project.godot`, `tests/streaming_validation.gd`, `tests/art_capture.gd`.

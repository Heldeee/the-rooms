# Escaliers, ouvertures et mobilier — 1 octobre 2026

## Corrections appliquées

- Le petit bloc de bois de la capture était une anomalie encastrée sans silhouette lisible. Il est remplacé par un équipement reconnaissable, orienté vers la salle : distributeur d'eau, casier ventilé, CRT sur chariot ou desserte d'entretien. Les mêmes familles enrichissent les salles d'archives et de service, en conservant les passages réservés.
- Grain du bois moins contrasté et moins dense : réduction de la cause probable du scintillement sur cet ancien objet. Les panneaux des nouveaux équipements sont espacés pour éviter les faces coplanaires. Le ressenti en mouvement devra encore être confirmé par le joueur ; une image seule ne prouve pas l'absence de scintillement.
- Altitude bornée entre 0 et 2,5 m, sans accumulation de pente au fil de l'exploration. Paliers plats sur plus de 87 % d'un parcours de 1 200 m testé. Escaliers de 16 marches pour les dénivelés de 1,5 m ; rampes de 1 m plus espacées sur l'autre axe.
- Marches et contremarches visibles, support physique continu pour une montée et une descente fluides sans saut. Ce choix évite le tremblement d'un contrôleur FPS contre chaque contremarche ; les marches n'ont pas chacune un collider séparé.
- Hauteur minimale et maximale de chaque salle échantillonnée : les murs restent fermés même lorsque le terrain redescend.
- Ouvertures déterministes communes aux deux salles : passage rectangulaire, arche à 24 segments, grands passages presque sans cloison et ouverts jusqu'au plafond commun. Les arches restent une approximation segmentée.
- Suppression des grilles verticales traversables dans les salles à 90°. La rotation reste lisible par les matériaux et les luminaires. Suppression de la chaise imposée dans toutes ces salles.

## Vérification

Godot 4.7.2, Forward+, RTX 4070 SUPER. Import et tests de génération sur plusieurs graines, passages, enveloppe fermée et reproductibilité : zéro échec. Même résultat avec rendu et captures des anomalies.

Test physique dédié `tests/stairs_validation.gd` : parcours dans les deux sens sur un escalier de 1,5 m, joueur au sol à l'arrivée, sans blocage. Capture réelle `../stairs-capture.png`, sans retouche.

Parcours rendu après préchargement lointain, 1920 × 1061 : 17 895 frames, médiane 1,147 ms, p95 1,939 ms, p99 2,542 ms, maximum 6,495 ms ; 9 transitions, 10 salles visitées, génération maximale 4,385 ms. Ces mesures concernent le parcours testé après échauffement, pas une garantie sur chaque machine ou sur le démarrage à froid.

Les avertissements Windows sur le magasin de certificats et la persistance des réglages/cache dans AppData restent liés à l'environnement restreint. Deux références audio fuient encore à la fermeture du test headless ; problème préexistant non corrigé dans cette passe.

## Limites restantes

Les props sont des silhouettes procédurales simples, sans nouveaux assets téléchargés. L'écho conserve sa famille de panneaux ; les quatre nouvelles familles diversifient le mobilier et les anomalies encastrées. Les salles ne se superposent pas encore sur plusieurs étages : cette passe ajoute des paliers et escaliers dans le réseau existant. Le budget de génération peut dépasser 2 ms pour une salle complexe, ce qui reste mesuré ci-dessus.

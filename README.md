# Flux

Application mobile (Android et iOS) qui affiche **en direct** la consommation de données du téléphone, canal par canal : **Wi-Fi, Mobile, USB, Bluetooth**.

- Un gros bouton **GO** pour lancer la capture, **STOP** pour l'arrêter.
- **Rien n'est enregistré par défaut** : les mesures vivent en mémoire pendant la capture, puis le résumé disparaît quand on quitte l'écran de fin. L'**historique** est un choix de l'utilisateur (désactivé au départ) : il ne garde que des résumés (date, durée, volumes par canal), sur le téléphone.
- **Rien n'est filtré** : l'app lit seulement les compteurs d'octets du système, jamais le contenu du trafic.
- **Rien n'est envoyé** : sur Android, l'app ne demande même pas la permission Internet.

## Capture en arrière-plan

Une fois GO appuyé, la capture continue jusqu'à STOP (dans l'app, dans la notification, ou arrêt automatique), même si l'on change d'app, éteint l'écran ou ferme Flux.

- **Android** : le service `CaptureService` fait lui-même la mesure (toutes les 2 s), affiche la notification « En direct » avec un bouton **STOP** et applique l'arrêt automatique. L'état de la capture (début, volumes, derniers compteurs) est sauvegardé pendant la capture (`CaptureState.kt`) puis effacé à l'arrêt. Si le système ferme Flux pour économiser la batterie, il relance le service ; sinon la capture reprend à la prochaine ouverture. Comme les compteurs du système sont cumulés, le temps passé sans lecture est rattrapé : les volumes restent justes (sauf après un redémarrage du téléphone). Les captures terminées sans l'app ouverte arrivent dans l'historique à l'ouverture suivante.
- **Économie de batterie** : certains fabricants (Samsung, Xiaomi, Huawei, Oppo…) coupent les apps en arrière-plan au bout de quelques minutes. Pendant une capture, Flux affiche un encart qui ouvre le réglage pour choisir « Ne pas optimiser » / « Sans restriction ».
- **iOS** : le système ne permet pas de mesurer en continu en arrière-plan. Le point de départ de la capture est sauvegardé ; au retour dans Flux (même après une fermeture), la capture reprend et les volumes sont recalculés à partir des compteurs du système. Limites : un redémarrage du téléphone clôt la capture sur le dernier état connu, et les compteurs 32 bits d'iOS ne sont rattrapés que pour un seul bouclage (4 Go) pendant l'absence.

## Consommation par app

L'écran « Consommation par app » a deux usages :

- **Pendant une capture** (mode « Capture ») : la part de chaque app depuis GO, à l'écran et en arrière-plan, Wi-Fi et mobile. À GO, Flux relève les compteurs cumulés de chaque app (`AppUsageReader.snapshot`, via `NetworkStatsManager`) ; à chaque lecture et à STOP, la différence donne ce que chaque app a consommé (`delta`). Chaque lecture force Android à relever ses compteurs, la différence est donc exacte, sans l'imprécision des tranches de 2 h. La part par app fait partie du résumé de fin de capture (et de l'historique, s'il est activé). Si l'accès « Données d'utilisation » est accordé après GO, la part est comptée à partir de ce moment, et l'écran le dit. Ce que la capture a mesuré sur le Wi-Fi et le mobile mais qu'aucune app ne revendique est affiché à part (« non attribué » : VPN, services du système…).
- **Historique du téléphone** (24 h, 7 j, 30 j) : les apps qui consomment en arrière-plan d'après les chiffres qu'Android garde déjà, par tranches d'environ 2 h. La période est arrondie à la tranche, sinon Android ne compte qu'une fraction de la tranche en cours et les derniers chiffres semblent manquer.

Dans les deux cas il faut l'accès spécial « Données d'utilisation », que l'utilisateur accorde dans les réglages ; l'écran l'explique et ouvre la bonne page. Chaque app ouvre un détail avec un bouton vers sa page de réglages, pour couper ses données en arrière-plan.

**Limites** : Android ne détaille pas l'USB ni le Bluetooth par app ; sur Android 9 et avant, le détail du réseau mobile demanderait une permission téléphone que Flux ne demande pas (seul le Wi-Fi est alors détaillé) ; **iPhone** : iOS ne donne à aucune app la consommation des autres apps, l'écran l'explique.

**VPN** : quand le Wi-Fi ne peut pas être lu directement (Android 10 et plus), il est déduit du total du téléphone, qui inclut le tunnel du VPN : le trafic du VPN peut alors être compté deux fois. L'écran de capture le signale.

## Écrans

| Écran | Rôle |
| --- | --- |
| Accueil | Bouton GO, état de chaque canal ; pendant une capture : STOP et débits en direct |
| Capture en cours | Débit total, courbe des 60 dernières secondes, débit par canal, STOP |
| Détail d'un canal | Débit entrant / sortant, courbe, volumes depuis GO, pic |
| Fin de session | Durée, volume total, répartition par canal, part par app |
| Consommation par app | Part de chaque app pendant la capture (en direct, puis dans le résumé) ; ou historique du téléphone sur 24 h, 7 j, 30 j |
| Historique | Bilan des 30 derniers jours, captures groupées par jour, détail, suppression (une capture ou tout) |
| Réglages | Unités (Mo/s, Mb/s, auto), thème (sombre, clair, système), canaux affichés, arrêt automatique, écran allumé, historique |
| Confidentialité | Promesses de l'app et permissions réellement utilisées |

Ce qui est gardé sur le téléphone (via `shared_preferences`) :

- les **réglages** ;
- si l'historique est activé, les **résumés de capture** (500 au plus, les plus anciens partent en premier). Une capture de moins de 3 s n'est pas gardée. Désactiver l'historique efface tous les résumés.

La sauvegarde automatique d'Android vers le cloud est désactivée (`allowBackup="false"`) : l'historique ne quitte pas le téléphone. Sur iPhone, il peut faire partie des sauvegardes de l'appareil (iCloud ou ordinateur) faites par l'utilisateur.

## Comment la mesure fonctionne

Le code Dart interroge le code natif toutes les secondes pendant une capture (toutes les 2 s sinon) via le canal `com.oseeeb.flux/traffic`. Le natif renvoie les **compteurs cumulés** de chaque canal ; le débit est calculé côté Dart (`lib/traffic/rate_meter.dart`).

| Canal | Android (`TrafficReader.kt`) | iOS (`TrafficPlugin.swift`) |
| --- | --- | --- |
| Wi-Fi | compteurs de l'interface Wi-Fi ; sinon total − autres canaux | interface `en0` |
| Mobile | `TrafficStats.getMobileRx/TxBytes()` | interfaces `pdp_ip*` |
| USB | partage de connexion (`rndis*`, `ncm*`) ou adaptateur Ethernet | adaptateurs `en2`+ |
| Bluetooth | partage de connexion Bluetooth (`bt-pan`) | non disponible |

### Limites connues

- **USB et Bluetooth** ne sont mesurables que lorsqu'ils transportent une connexion réseau (partage de connexion, adaptateur). Le trafic d'un casque Bluetooth ou d'un transfert de fichiers par câble n'est pas exposé par les systèmes. L'app l'affiche honnêtement (« Non mesurable » / « Non disponible »).
- Sur Android récent, la lecture directe des compteurs par interface peut être bloquée : le Wi-Fi est alors déduit (total − mobile − autres canaux).
- Sur iOS, les compteurs sont sur 32 bits et repartent de zéro après 4 Go ; c'est géré dans le calcul.
- Le code natif n'a pas encore été testé sur de vrais téléphones.

## Lancer le projet

Prérequis : [Flutter](https://docs.flutter.dev/get-started/install) 3.47 ou plus récent, Android Studio (Android) et/ou Xcode (iOS).

```bash
flutter pub get
flutter run            # sur un téléphone ou un émulateur branché
flutter test           # tests automatiques
flutter analyze        # vérification du code
```

> Sur un émulateur, les chiffres de trafic sont peu parlants : testez de préférence sur un vrai téléphone.

## Organisation du code

```
lib/
  main.dart                 démarrage, thème, cycle de vie
  app/                      réglages, palette sombre/claire, accès partagé
  traffic/                  lecture native, calcul des débits, session de capture
  history/                  historique des résumés (si activé)
  apps/                     consommation par app (analyse)
  ui/screens/               les huit écrans
  ui/widgets/               bouton GO, graphique en direct, composants communs
android/app/src/main/kotlin/com/oseeeb/flux/   lecture des compteurs Android
ios/Runner/TrafficPlugin.swift                  lecture des compteurs iOS
test/                       tests du calcul, du format et du parcours GO → STOP
```

## Logo et icône

Le logo part de la proposition d'origine (`docs/logo/proposition_originale.webp`), recolorée aux couleurs de l'app (vert citron `#C6F432` et blanc sur fond `#0B0F1A`) par `tool/recolor_logo.py`.

- `assets/brand/flux_icon.png` : icône complète (iOS, en-tête de l'app).
- `assets/brand/flux_icon_foreground.png` : motif seul pour l'icône adaptative Android.

Après une modification : `dart run flutter_launcher_icons` régénère toutes les tailles. Pensez à annuler la modification que l'outil fait à tort dans `ios/Runner.xcodeproj/project.pbxproj` (`git checkout` de ce fichier).

## Polices

Manrope et Space Grotesk sont embarquées dans l'app (`assets/fonts/`, licence SIL Open Font License) : rien n'est téléchargé au lancement.

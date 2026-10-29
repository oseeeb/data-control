# Flux

Application mobile (Android et iOS) qui affiche **en direct** la consommation de données du téléphone, canal par canal : **Wi-Fi, Mobile, USB, Bluetooth**.

- Un gros bouton **GO** pour lancer la capture, **STOP** pour l'arrêter.
- **Rien n'est enregistré** : les mesures vivent en mémoire pendant la capture, puis le résumé disparaît quand on quitte l'écran de fin. Aucun historique.
- **Rien n'est filtré** : l'app lit seulement les compteurs d'octets du système, jamais le contenu du trafic.
- **Rien n'est envoyé** : sur Android, l'app ne demande même pas la permission Internet.

## Capture en arrière-plan

Une fois GO appuyé, la capture continue jusqu'à STOP, même si l'on change d'écran ou d'app.

- **Android** : un service au premier plan garde Flux actif et affiche une notification « En direct » (débit, volume depuis GO) avec un bouton **STOP**. Un verrou de veille partiel permet de continuer écran éteint ; il est libéré à l'arrêt (et au plus tard après 6 h). Fermer Flux depuis les apps récentes arrête la capture.
- **iOS** : le système ne permet pas de mesurer en continu en arrière-plan. La capture reprend au retour dans Flux ; comme les compteurs du système sont cumulés, les volumes du temps passé ailleurs restent justes.

## Écrans

| Écran | Rôle |
| --- | --- |
| Accueil | Bouton GO, état de chaque canal ; pendant une capture : STOP et débits en direct |
| Capture en cours | Débit total, courbe des 60 dernières secondes, débit par canal, STOP |
| Détail d'un canal | Débit entrant / sortant, courbe, volumes depuis GO, pic |
| Fin de session | Durée, volume total, répartition par canal |
| Réglages | Unités (Mo/s, Mb/s, auto), thème (sombre, clair, système), canaux affichés, arrêt automatique, écran allumé |
| Confidentialité | Promesses de l'app et permissions réellement utilisées |

Les seules choses gardées sur le téléphone sont les **réglages** (via `shared_preferences`).

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
  ui/screens/               les six écrans
  ui/widgets/               bouton GO, graphique en direct, composants communs
android/app/src/main/kotlin/com/oseeeb/flux/   lecture des compteurs Android
ios/Runner/TrafficPlugin.swift                  lecture des compteurs iOS
test/                       tests du calcul, du format et du parcours GO → STOP
```

## Polices

Manrope et Space Grotesk sont embarquées dans l'app (`assets/fonts/`, licence SIL Open Font License) : rien n'est téléchargé au lancement.

# DisplayDeck

Petite app de barre de menu macOS pour piloter ses écrans :

- **Luminosité** de l'écran intégré (luminosité matérielle) et **assombrissement logiciel** de n'importe quel écran, via la table gamma.
- **Écrans virtuels HiDPI** (presets 1920×1080, 2560×1440 et 1440×900 en points), utiles pour un enregistrement, un partage d'écran ou des tests de mise en page.
- **DDC/CI** pour les écrans externes : luminosité et volume réglés directement sur le moniteur.
- **Changement de résolution** parmi tous les modes disponibles, HiDPI compris.

## Prérequis

- macOS 13 ou plus récent.
- Mac Apple Silicon pour le DDC.
- Outils de ligne de commande Xcode (Swift 6).

## Build et lancement

```sh
./scripts/build-app.sh
open build/DisplayDeck.app
```

Le script compile en release avec SwiftPM, assemble `build/DisplayDeck.app` et le signe en ad hoc. L'app n'a pas d'icône dans le Dock : elle apparaît uniquement dans la barre de menu.

Pour un build de développement : `swift build` puis `.build/debug/DisplayDeck`.

## Limites

- L'app s'appuie sur des API privées d'Apple (DisplayServices, classes `CGVirtualDisplay` de CoreGraphics, `IOAVService` d'IOKit). Elles ne sont pas documentées et peuvent changer ou disparaître à n'importe quelle mise à jour de macOS.
- Pour la même raison, l'app n'est pas distribuable sur le Mac App Store.
- Le DDC n'a pas pu être testé faute d'écran externe. Selon le moniteur et la connectique (certains docks, adaptateurs ou ports HDMI ne relaient pas le DDC), les sliders DDC peuvent ne pas apparaître ou rester sans effet.
- Deux moniteurs strictement identiques peuvent être associés dans le désordre, l'association se faisant sur le fabricant et le modèle lus dans l'EDID.
- La résolution d'un écran virtuel se choisit à sa création. Si on la change ensuite (par exemple dans Réglages Système), macOS ne retire plus cet écran avant la fermeture de DisplayDeck.
- L'assombrissement logiciel remplace temporairement la courbe de calibration ; elle est restaurée en remettant le slider au maximum ou en quittant l'app.

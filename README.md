# EvaluaTest Android Native

Rebuild native Android de **EvaluaTest** en **Flutter**, avec une base pensée pour une expérience mobile premium, fluide et stable.

## Objectif

Remplacer l’ancienne approche WebView/Capacitor par une vraie application mobile native dans son comportement, avec :

- UI/UX premium
- navigation mobile-first
- architecture propre et maintenable
- moteur d’examen fiable
- résultats et correction élégants

## Base actuelle

Cette première base inclut déjà :

- un projet Flutter Android propre
- une home premium de départ
- l’import des données de questions existantes depuis les JSON historiques
- un premier build APK debug validé

## Structure prévue

- `lib/` : app Flutter
- `assets/questions/` : base de questions importée depuis l’existant
- `android/` : projet Android généré par Flutter

## Commandes utiles

```bash
export PATH="/Users/utente/.openclaw/workspace/.tools/flutter/bin:$PATH"
cd android_projects/EvaluaTest-AndroidNative
flutter pub get
flutter run
flutter build apk --debug
```

## Prochaines étapes

1. définir le design system final
2. construire le vrai flow auth natif
3. implémenter le moteur d’examen
4. ajouter dashboard, historique et résultats
5. sortir une APK de test UX sur téléphone réel

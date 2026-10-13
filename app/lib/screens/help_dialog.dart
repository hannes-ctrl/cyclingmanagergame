import 'package:flutter/material.dart';
import 'package:sim/sim.dart';

import '../app_state.dart';
import '../ui.dart';
import '../widgets.dart';

/// How a season is played, in a few steps.
const _steps = <(String, String)>[
  (
    'Weiter',
    'Der Knopf oben rechts (oder die Leertaste) lässt die Tage laufen, bis etwas dein Team betrifft: ein Rennen, eine Nachricht, eine Rückfrage aus dem Rennen.',
  ),
  (
    'Saisonplan',
    'Der Sportliche Leiter hat alle Rennen der Saison geplant. Im Rennplaner änderst du einzelne Einsätze; auf der Fahrerseite setzt du mit der Zielscheibe Saisonziele, auf die ein Fahrer seine Form ausrichtet.',
  ),
  (
    'Rennvorbereitung',
    'Vor jedem Rennen bestätigst du das Aufgebot. Mit eigener Taktik legst du einzelne Rollen fest (Nadel) oder alles; den Rest plant der Sportliche Leiter je Etappe.',
  ),
  (
    'Funk',
    'Im Rennen meldet sich der Sportliche Leiter bis zu dreimal. Die markierte Antwort ist seine Empfehlung. Unter „Aufgabenverteilung" lässt sich der Funk abschalten.',
  ),
  (
    'Fahrer',
    'Moral, Versprechen und Persönlichkeit stehen auf der Fahrerseite. Der Stern setzt fremde Fahrer auf die Beobachtungsliste, die Waage vergleicht zwei Fahrer.',
  ),
  (
    'Tastatur',
    'Leertaste: weiter. Esc oder Alt+←: zurück. Strg+F: Fahrersuche. Pfeiltasten und Enter: durch Listen und von Fahrer zu Fahrer.',
  ),
];

/// Opens the help: a short introduction and the glossary of all figures.
///
/// @param context Build context.
/// @param state Application state.
/// @returns A future that completes when the dialog is closed.
Future<void> showHelpDialog(BuildContext context, AppState state) {
  final c = state.colors;
  final terms = statHelp.entries.toList()
    ..sort(
      (a, b) => tr(a.key).toLowerCase().compareTo(tr(b.key).toLowerCase()),
    );
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: c.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('Hilfe'), style: headStyle(23))),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Schließen')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    Label(tr('So läuft eine Saison')),
                    const SizedBox(height: 6),
                    for (final (title, text) in _steps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                tr(title),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                tr(text),
                                style: const TextStyle(height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Label(tr('Begriffe')),
                    const SizedBox(height: 6),
                    for (final e in terms)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                tr(e.key),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                tr(e.value),
                                style: const TextStyle(
                                  height: 1.4,
                                  color: TeamColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

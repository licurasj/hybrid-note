import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../backend/firestore_setup.dart';
import '../l10n/generated/app_localizations.dart';

// On the empty home after the starter lists could not be written (Q-27): a
// plain note with "Try again" and "Start empty". Nothing otherwise. T-16
// restyles it with the home.
class StarterNote extends StatelessWidget {
  const StarterNote({super.key});

  @override
  Widget build(BuildContext context) {
    final StarterSeeding seeding = context.read<StarterSeeding>();
    return ListenableBuilder(
      listenable: seeding.changes,
      builder: (context, _) {
        if (seeding.status != StarterStatus.failed) {
          return const SizedBox.shrink();
        }
        final AppLocalizations loc = AppLocalizations.of(context);
        return Card(
          key: const ValueKey('starter-failed'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.starterListsFailed),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('starter-retry'),
                      onPressed: seeding.retry,
                      child: Text(loc.tryAgain),
                    ),
                    OutlinedButton(
                      key: const ValueKey('starter-empty'),
                      onPressed: seeding.startEmpty,
                      child: Text(loc.startEmpty),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

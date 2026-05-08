import 'package:flutter/material.dart';
import '../models/flight.dart';

class TankGauge extends StatelessWidget {
  final TankConfig tank;
  final bool isActive;
  /// When provided, gauge fill and number display use this estimated value
  /// instead of [tank.remaining]. Displayed with '~' prefix and amber colour
  /// to signal it is a live estimate, not a confirmed reading.
  final double? estimatedRemaining;

  const TankGauge({
    super.key,
    required this.tank,
    required this.isActive,
    this.estimatedRemaining,
  });

  Color _levelColor(double pct, {bool estimated = false}) {
    if (estimated) {
      // Amber palette for estimation mode
      if (pct > 0.4) return const Color(0xFFFFB300);
      if (pct > 0.2) return const Color(0xFFFF6F00);
      return const Color(0xFFD50000);
    }
    if (pct > 0.4) return const Color(0xFF00C853);
    if (pct > 0.2) return const Color(0xFFFFD600);
    return const Color(0xFFD50000);
  }

  @override
  Widget build(BuildContext context) {
    final isEstimated = estimatedRemaining != null;
    final displayRemaining =
        isEstimated ? estimatedRemaining! : tank.remaining;
    final displayConsumed = tank.initialFuel - displayRemaining;

    final pct = (tank.capacity > 0 ? displayRemaining / tank.capacity : 0.0)
        .clamp(0.0, 1.0);
    final levelColor = _levelColor(pct, estimated: isEstimated);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF0D2137) : const Color(0xFF0A1A2E),
        border: Border.all(
          color:
              isActive ? const Color(0xFF00B0FF) : const Color(0xFF1E3A5F),
          width: isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isActive)
                const Icon(Icons.local_gas_station,
                    color: Color(0xFF00B0FF), size: 18),
              if (isActive) const SizedBox(width: 4),
              Text(
                tank.name,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF00B0FF)
                      : const Color(0xFF8BA7C0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Vertical gauge
          Container(
            width: 48,
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF1E3A5F), width: 1.5),
              borderRadius: BorderRadius.circular(6),
              color: const Color(0xFF071220),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                FractionallySizedBox(
                  heightFactor: pct,
                  child: Container(
                    decoration: BoxDecoration(
                      color: levelColor.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // Tick marks
                ...List.generate(4, (i) {
                  final top = 100 * (i + 1) / 5;
                  return Positioned(
                    top: top,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 1,
                      color: const Color(0xFF1E3A5F),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Remaining value — prefix '~' when estimated
          Text(
            '${isEstimated ? '~' : ''}${displayRemaining.toStringAsFixed(1)}',
            style: TextStyle(
              color: levelColor,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'gal',
            style: const TextStyle(color: Color(0xFF8BA7C0), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Cons: ${displayConsumed.clamp(0.0, double.infinity).toStringAsFixed(1)} gal',
            style: const TextStyle(color: Color(0xFF5A7A9A), fontSize: 12),
          ),

          // Estimation label
          if (isEstimated)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ESTIMADO',
                style: TextStyle(
                  color: Color(0xFFFFB300),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),

          if (isActive)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00B0FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ATIVO',
                style: TextStyle(
                  color: Color(0xFF00B0FF),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

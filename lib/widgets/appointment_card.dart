import 'package:flutter/material.dart';
import '../models/appointment.dart';
import '../utils/constants.dart';

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsApp;
  final bool showDate;
  final String? customerPhone;

  const AppointmentCard({
    super.key,
    required this.appointment,
    this.onTap,
    this.onComplete,
    this.onCall,
    this.onWhatsApp,
    this.showDate = false,
    this.customerPhone,
  });

  @override
  Widget build(BuildContext context) {
    final isPast = appointment.fullDateTime.isBefore(DateTime.now());
    final isInactive =
        appointment.status == AppointmentStatus.cancelled ||
        appointment.status == AppointmentStatus.noShow;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: appointment.isCompleted
              ? AppColors.surface.withValues(alpha: 0.5)
              : isInactive
              ? AppColors.surface.withValues(alpha: 0.7)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: appointment.isCompleted
                ? AppColors.green.withValues(alpha: 0.3)
                : isPast
                ? AppColors.red.withValues(alpha: 0.3)
                : AppColors.divider,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time column
                  Container(
                    constraints: const BoxConstraints(minWidth: 60),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: appointment.isCompleted
                          ? AppColors.green.withValues(alpha: 0.15)
                          : AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (showDate) ...[
                          Text(
                            '${appointment.appointmentDate.day.toString().padLeft(2, '0')}/${appointment.appointmentDate.month.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: appointment.isCompleted
                                  ? AppColors.green
                                  : AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        Text(
                          appointment.appointmentTime,
                          style: TextStyle(
                            color: appointment.isCompleted
                                ? AppColors.green
                                : AppColors.gold,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Customer info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appointment.customerName,
                          style: TextStyle(
                            color: appointment.isCompleted
                                ? AppColors.textSecondary
                                : AppColors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            decoration: appointment.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (customerPhone != null &&
                            customerPhone!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            customerPhone!,
                            style: TextStyle(
                              color: appointment.isCompleted
                                  ? AppColors.textSecondary.withValues(
                                      alpha: 0.5,
                                    )
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              decoration: appointment.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        _infoLine(
                          Icons.content_cut,
                          'Hizmet',
                          '${appointment.serviceName ?? 'Belirtilmedi'} · ${appointment.durationMinutes} dk',
                        ),
                        if (appointment.hairstyleName != null &&
                            appointment.hairstyleName!.isNotEmpty)
                          _infoLine(
                            Icons.face_outlined,
                            'Saç modeli',
                            appointment.hairstyleName!,
                          ),
                        const SizedBox(height: 6),
                        _statusChip(appointment.status),
                        if (appointment.notes != null &&
                            appointment.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            appointment.notes!,
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.7,
                              ),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (onCall != null ||
                  onWhatsApp != null ||
                  (onComplete != null && !isInactive)) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Phone call button
                    if (onCall != null) ...[
                      IconButton.filledTonal(
                        onPressed: onCall,
                        tooltip: 'Müşteriyi ara',
                        icon: const Icon(Icons.phone),
                        color: AppColors.green,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          backgroundColor: AppColors.green.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // WhatsApp button
                    if (onWhatsApp != null) ...[
                      IconButton.filledTonal(
                        onPressed: onWhatsApp,
                        tooltip: 'WhatsApp mesajı hazırla',
                        icon: const Icon(Icons.chat),
                        color: const Color(0xFF25D366),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          backgroundColor: const Color(
                            0xFF25D366,
                          ).withValues(alpha: 0.15),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Hairstyle thumbnail or complete button
                    if (onComplete != null &&
                        !isInactive &&
                        (!appointment.isCompleted || !isPast))
                      IconButton.filled(
                        onPressed: onComplete,
                        tooltip: appointment.isCompleted
                            ? 'Tamamlamayı geri al'
                            : 'Randevuyu tamamla',
                        icon: Icon(
                          appointment.isCompleted ? Icons.undo : Icons.check,
                        ),
                        color: AppColors.background,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          backgroundColor: appointment.isCompleted
                              ? AppColors.textSecondary
                              : AppColors.green,
                        ),
                      ),
                    if (appointment.isCompleted && isPast)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.green,
                        size: 24,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: AppColors.gold.withValues(alpha: 0.7)),
      const SizedBox(width: 4),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(color: AppColors.white),
              ),
            ],
          ),
          style: const TextStyle(fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  Widget _statusChip(AppointmentStatus status) {
    final (label, color) = switch (status) {
      AppointmentStatus.planned => ('Planlandı', AppColors.gold),
      AppointmentStatus.completed => ('Tamamlandı', AppColors.green),
      AppointmentStatus.cancelled => ('İptal edildi', AppColors.red),
      AppointmentStatus.noShow => ('Gelmedi', AppColors.gold),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

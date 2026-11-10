import '../models/appointment.dart';
import '../models/barber_service.dart';
import '../models/customer.dart';
import '../models/working_schedule.dart';
import 'alarm_scheduling.dart';
import 'database_service.dart';
import 'notification_service.dart';

class AppointmentFormGateway {
  const AppointmentFormGateway();

  Future<List<BarberService>> services() =>
      DatabaseService.instance.getServices(activeOnly: false);
  Future<Customer?> customer(int id) =>
      DatabaseService.instance.getCustomerById(id);
  Future<List<WorkingInterval>> workingIntervals() =>
      DatabaseService.instance.getWorkingIntervals();
  Future<List<ClosedTimeBlock>> closedBlocks() =>
      DatabaseService.instance.getClosedTimeBlocks();
  Future<bool> isTaken(Appointment appointment, {int? excludeId}) =>
      DatabaseService.instance.isTimeSlotTaken(
        appointment.appointmentDate,
        appointment.appointmentTime,
        durationMinutes: appointment.durationMinutes,
        excludeId: excludeId,
      );
  Future<Appointment> save({
    required Appointment appointment,
    required int? selectedCustomerId,
    required String phone,
    AppointmentStatus? expectedStatus,
  }) => DatabaseService.instance.saveAppointmentForCustomer(
    appointment: appointment,
    selectedCustomerId: selectedCustomerId,
    phone: phone,
    expectedStatus: expectedStatus,
  );
  Future<AlarmScheduleResult> syncAlarm(
    Appointment appointment, {
    required bool editing,
  }) async {
    if (editing) {
      await NotificationService.instance.cancelAlarm(appointment.id!);
    }
    return NotificationService.instance.scheduleAlarm(appointment);
  }
}

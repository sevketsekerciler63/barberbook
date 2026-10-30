class BackupPreview {
  final int schemaVersion;
  final int customerCount;
  final int appointmentCount;
  final int serviceCount;
  final int paymentCount;
  final int transactionCount;

  const BackupPreview({
    required this.schemaVersion,
    required this.customerCount,
    required this.appointmentCount,
    required this.serviceCount,
    required this.paymentCount,
    required this.transactionCount,
  });
}

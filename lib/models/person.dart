import 'package:hive/hive.dart';

part 'person.g.dart';

@HiveType(typeId: 0)
class Person extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String employeeId;

  @HiveField(3)
  List<double> faceEmbedding;

  @HiveField(4)
  DateTime registeredAt;

  Person({
    required this.id,
    required this.name,
    required this.employeeId,
    required this.faceEmbedding,
    required this.registeredAt,
  });
}

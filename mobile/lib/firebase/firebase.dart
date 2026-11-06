import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
@NowaGenerated()
class FirebaseService {
  factory FirebaseService() {
    return _instance;
  }

  FirebaseService._();

  static final FirebaseService _instance = FirebaseService._();
  @NowaGenerated({'loader': 'firestore_getter'})
  static FirebaseFirestore get firestore {
    return FirebaseFirestore.instance;
  }
}

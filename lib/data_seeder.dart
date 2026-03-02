import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> seedHostelData() async {
  final firestore = FirebaseFirestore.instance;
  final currentUser = FirebaseAuth.instance.currentUser;

  try {
    print('Seeding database...');

    // 1. Ensure Room Types Exist (Reuse if available to avoid duplicates)
    final List<Map<String, dynamic>> roomTypesData = [
      {'name': 'Single Room', 'capacity': 1, 'price': 1000},
      {'name': 'Double Room', 'capacity': 2, 'price': 1500},
      {'name': 'Dormitory Bed', 'capacity': 1, 'price': 500},
    ];

    print('Checking/Creating room types...');
    List<String> roomTypeIds = [];

    for (var typeData in roomTypesData) {
      final String typeName = typeData['name'];
      final existingTypeQuery = await firestore
          .collection('room_types')
          .where('name', isEqualTo: typeName)
          .limit(1)
          .get();

      if (existingTypeQuery.docs.isNotEmpty) {
        // print('Using existing room type: $typeName');
        roomTypeIds.add(existingTypeQuery.docs.first.id);
      } else {
        print('Creating new room type: $typeName');
        final typeRef = await firestore.collection('room_types').add({
          ...typeData,
          'createdAt': FieldValue.serverTimestamp(),
        });
        roomTypeIds.add(typeRef.id);
      }
    }

    /*
    // 2. Seed Hostels (A to F)
    final List<String> hostelNames = [
      'Hostel A',
      'Hostel B',
      'Hostel C',
      'Hostel D',
      'Hostel E',
      'Hostel F',
    ];

    final List<String> imageUrls = [
      'https://images.unsplash.com/photo-1555854877-bab0e564b8d5?auto=format&fit=crop&w=600&q=80',
      'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?auto=format&fit=crop&w=600&q=80',
      'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=600&q=80',
    ];

    for (final name in hostelNames) {
      print('Creating $name...');

      final hostelRef = await firestore.collection('hostels').add({
        'name': name,
        'totalRooms': 20,
        'availableRooms': 20,
        'imageUrls': imageUrls,
        'imageUrl': imageUrls[0],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create Rooms for this Hostel
      final WriteBatch batch = firestore.batch();
      for (int i = 1; i <= 20; i++) {
        final roomRef = firestore.collection('rooms').doc();
        // Cycle room types
        final roomTypeId = roomTypeIds[(i - 1) % roomTypeIds.length];

        batch.set(roomRef, {
          'hostelId': hostelRef.id,
          'name': 'Room $i',
          'roomTypeId': roomTypeId,
          'isAvailable': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    */

    // 2. Clear existing rooms and add new ones sequentially across hostels
    print('Clearing existing rooms...');
    final existingRoomsQuery = await firestore.collection('rooms').get();

    WriteBatch deleteBatch = firestore.batch();
    int deleteOpsCount = 0;

    for (var doc in existingRoomsQuery.docs) {
      deleteBatch.delete(doc.reference);
      deleteOpsCount++;
      if (deleteOpsCount >= 400) {
        // Limit to 400 to be safe with Firebase limits
        await deleteBatch.commit();
        deleteBatch = firestore.batch();
        deleteOpsCount = 0;
      }
    }
    if (deleteOpsCount > 0) {
      await deleteBatch.commit();
    }
    print('Cleared ${existingRoomsQuery.docs.length} existing rooms.');

    print('Fetching existing hostels...');
    final hostelQuery = await firestore.collection('hostels').get();

    if (hostelQuery.docs.isEmpty) {
      print('No hostels found. Please create hostels first.');
    } else {
      // Sort hostels by name for consistent room distribution (Hostel A -> Hostel B -> ...)
      final sortedHostels = hostelQuery.docs.toList()
        ..sort((a, b) {
          final nameA = a.data()['name']?.toString() ?? '';
          final nameB = b.data()['name']?.toString() ?? '';
          return nameA.compareTo(nameB);
        });

      int globalRoomCounter = 1;

      for (final hostelDoc in sortedHostels) {
        final hostelId = hostelDoc.id;
        final hostelName = hostelDoc.data()['name'] ?? 'Unknown Hostel';
        print('Creating 5 rooms for $hostelName...');

        final WriteBatch batch = firestore.batch();
        // Create 5 rooms
        for (int i = 0; i < 5; i++) {
          final roomRef = firestore.collection('rooms').doc();
          // Cycle room types safely
          final roomTypeId =
              roomTypeIds[(globalRoomCounter - 1) % roomTypeIds.length];
          // Determine sequential name
          final roomName = 'Room $globalRoomCounter';

          batch.set(roomRef, {
            'hostelId': hostelId,
            'name': roomName,
            'roomTypeId': roomTypeId,
            'isAvailable': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

          globalRoomCounter++;
        }
        await batch.commit();
        print('Added 5 rooms to $hostelName');
      }
    }

    // 3. Seed current user document (once)
    // if (currentUser != null) {
    //   await firestore.collection('users').doc(currentUser.uid).set({
    //     'name': 'Test User',
    //     'email': currentUser.email ?? 'test@email.com',
    //     'phone': '08012345678',
    //     'location': 'Lagos, Nigeria',
    //     'avatarUrl': null,
    //     'createdAt': FieldValue.serverTimestamp(),
    //   }, SetOptions(merge: true));
    //   print('User document updated: ${currentUser.uid}');
    // }

    print('Seeding completed successfully!');
  } catch (e) {
    print('Error seeding data: $e');
  }
}

/// Creates an admin user in Firebase Auth + Firestore.
/// Call this once, e.g. from a button on a debug screen or from main().
/// If the admin already exists it will skip creation.
Future<void> seedAdminUser() async {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  const adminEmail = 'madukajesse14@gmail.com';
  const adminPassword = 'JesusISking';
  const adminRegNumber = 'ADMIN001';

  try {
    print('🔧 Seeding admin user...');

    // Check if admin already exists in Firestore by regNumber
    final existing = await firestore
        .collection('users')
        .where('regNumber', isEqualTo: adminRegNumber)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      print('✅ Admin user already exists, skipping.');
      return;
    }

    // Create in Firebase Auth
    final credential = await auth.createUserWithEmailAndPassword(
      email: adminEmail,
      password: adminPassword,
    );

    final user = credential.user;
    if (user == null) {
      print('❌ Failed to create admin user in Auth.');
      return;
    }

    // Store admin doc in Firestore
    await firestore.collection('users').doc(user.uid).set({
      'firstName': 'Admin',
      'lastName': 'User',
      'regNumber': adminRegNumber,
      'department': 'Administration',
      'email': adminEmail,
      'phone': '',
      'gender': '',
      'role': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
    });

    print('✅ Admin user created successfully!');
    print('   Email: $adminEmail');
    print('   Reg Number: $adminRegNumber');
    print('   UID: ${user.uid}');

    // Sign out so the app doesn't stay logged in as admin
    await auth.signOut();
  } on FirebaseAuthException catch (e) {
    if (e.code == 'email-already-in-use') {
      print('⚠️ Admin email already in Auth. Checking Firestore...');
      // Try to sign in to get the UID and ensure Firestore doc exists
      try {
        final cred = await auth.signInWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
        final uid = cred.user?.uid;
        if (uid != null) {
          await firestore.collection('users').doc(uid).set({
            'firstName': 'Admin',
            'lastName': 'User',
            'regNumber': adminRegNumber,
            'department': 'Administration',
            'email': adminEmail,
            'phone': '',
            'gender': '',
            'role': 'admin',
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          print('✅ Admin Firestore doc created/merged for UID: $uid');
        }
        await auth.signOut();
      } catch (e2) {
        print('❌ Could not reconcile admin: $e2');
      }
    } else {
      print('❌ Error creating admin: ${e.message}');
    }
  } catch (e) {
    print('❌ Error seeding admin: $e');
  }
}

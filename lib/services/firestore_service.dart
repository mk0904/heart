import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== USERS ====================
  
  /// Get user by ID
  Future<UserProfile?> getUser(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      return UserProfile.fromFirestore(data, doc.id);
    } catch (e) {
      throw Exception('Failed to get user: ${e.toString()}');
    }
  }

  /// Get all users (optionally filtered by college)
  Future<List<UserProfile>> getUsers({String? collegeId}) async {
    try {
      Query query = _firestore.collection('users');
      
      // Filter by 'college' field (which contains the collegeId)
      if (collegeId != null) {
        query = query.where('college', isEqualTo: collegeId);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return UserProfile.fromFirestore(data, doc.id);
          })
          .toList();
    } catch (e) {
      throw Exception('Failed to get users: ${e.toString()}');
    }
  }

  /// Stream users (real-time updates)
  Stream<List<UserProfile>> streamUsers({String? collegeId}) {
    Query query = _firestore.collection('users');
    
    // Filter by 'college' field (which contains the collegeId)
    if (collegeId != null) {
      query = query.where('college', isEqualTo: collegeId);
    }

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return UserProfile.fromFirestore(data, doc.id);
        })
        .toList());
  }

  /// Update user profile
  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(userId).update(data);
    } catch (e) {
      throw Exception('Failed to update user: ${e.toString()}');
    }
  }

  // ==================== PROJECTS ====================

  /// Get projects (optionally filtered by college)
  Future<List<Map<String, dynamic>>> getProjects({String? collegeId}) async {
    try {
      Query query = _firestore.collection('projects');
      
      if (collegeId != null) {
        query = query.where('collegeId', isEqualTo: collegeId);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              ...data,
              // Ensure submissionsCount is a number
              'submissionsCount': data['submissionsCount'] ?? 0,
            };
          })
          .toList();
    } catch (e) {
      throw Exception('Failed to get projects: ${e.toString()}');
    }
  }

  /// Stream projects (real-time updates)
  Stream<List<Map<String, dynamic>>> streamProjects({String? collegeId}) {
    Query query = _firestore.collection('projects');
    
    if (collegeId != null) {
      query = query.where('collegeId', isEqualTo: collegeId);
    }

    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {'id': doc.id, ...data};
        })
        .toList());
  }

  /// Get project by ID
  Future<Map<String, dynamic>?> getProject(String projectId) async {
    try {
      final doc = await _firestore.collection('projects').doc(projectId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      return {'id': doc.id, ...data};
    } catch (e) {
      throw Exception('Failed to get project: ${e.toString()}');
    }
  }

  /// Update project submissions count
  Future<void> updateProjectSubmissionsCount(String projectId) async {
    try {
      await _firestore.collection('projects').doc(projectId).update({
        'submissionsCount': FieldValue.increment(1),
      });
    } catch (e) {
      throw Exception('Failed to update project: ${e.toString()}');
    }
  }

  // ==================== SUBMISSIONS ====================

  /// Get submissions for a project
  Future<List<Map<String, dynamic>>> getSubmissions(String projectId) async {
    try {
      // Fetch without orderBy to avoid index requirement, then sort client-side
      final snapshot = await _firestore
          .collection('submissions')
          .where('projectId', isEqualTo: projectId)
          .limit(100) // Limit to prevent fetching too many records
          .get();
      
      List<Map<String, dynamic>> submissions = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              ...data,
              // Ensure images array exists
              'images': data['images'] ?? [],
              'percentage': data['percentage'] ?? 0,
              'notes': data['notes'] ?? '',
            };
          })
          .toList();
      
      // Sort manually by createdAt (descending)
      submissions.sort((a, b) {
        int getTimestamp(Map<String, dynamic> submission) {
          final createdAt = submission['createdAt'];
          if (createdAt == null) return 0;
          if (createdAt is Timestamp) {
            return createdAt.millisecondsSinceEpoch;
          }
          if (createdAt is Map && createdAt['seconds'] != null) {
            return (createdAt['seconds'] as int) * 1000;
          }
          if (createdAt is String) {
            try {
              return DateTime.parse(createdAt).millisecondsSinceEpoch;
            } catch (e) {
              return 0;
            }
          }
          if (createdAt is int) {
            return createdAt;
          }
          return 0;
        }
        return getTimestamp(b) - getTimestamp(a); // Descending order
      });
      
      return submissions;
    } catch (e) {
      throw Exception('Failed to get submissions: ${e.toString()}');
    }
  }
  
  /// Stream submissions for a project (real-time updates)
  Stream<List<Map<String, dynamic>>> streamSubmissions(String projectId) {
    // Fetch without orderBy to avoid index requirement, then sort client-side
    return _firestore
        .collection('submissions')
        .where('projectId', isEqualTo: projectId)
        .limit(100) // Limit to prevent fetching too many records
        .snapshots()
        .map((snapshot) {
          List<Map<String, dynamic>> submissions = snapshot.docs
              .map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return {
                  'id': doc.id,
                  ...data,
                  // Ensure images array exists
                  'images': data['images'] ?? [],
                  'percentage': data['percentage'] ?? 0,
                  'notes': data['notes'] ?? '',
                };
              })
              .toList();
          
          // Sort manually by createdAt (descending)
          submissions.sort((a, b) {
            int getTimestamp(Map<String, dynamic> submission) {
              final createdAt = submission['createdAt'];
              if (createdAt == null) return 0;
              if (createdAt is Timestamp) {
                return createdAt.millisecondsSinceEpoch;
              }
              if (createdAt is Map && createdAt['seconds'] != null) {
                return (createdAt['seconds'] as int) * 1000;
              }
              if (createdAt is String) {
                try {
                  return DateTime.parse(createdAt).millisecondsSinceEpoch;
                } catch (e) {
                  return 0;
                }
              }
              if (createdAt is int) {
                return createdAt;
              }
              return 0;
            }
            return getTimestamp(b) - getTimestamp(a); // Descending order
          });
          
          return submissions;
        });
  }

  /// Add a new submission
  Future<String> addSubmission(Map<String, dynamic> submissionData) async {
    try {
      final docRef = await _firestore
          .collection('submissions')
          .add(submissionData);
      
      // Update project submissions count
      if (submissionData['projectId'] != null) {
        await updateProjectSubmissionsCount(submissionData['projectId']);
      }
      
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to add submission: ${e.toString()}');
    }
  }

  /// Update a submission
  Future<void> updateSubmission(String submissionId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('submissions').doc(submissionId).update(data);
    } catch (e) {
      throw Exception('Failed to update submission: ${e.toString()}');
    }
  }

  // ==================== CIRCULARS ====================

  /// Get circulars (optionally filtered by user)
  Future<List<Map<String, dynamic>>> getCirculars({String? userId}) async {
    try {
      QuerySnapshot snapshot;
      
      if (userId != null) {
        // Use arrayContains without orderBy (no index available)
        // We'll sort client-side instead
        snapshot = await _firestore
            .collection('circulars')
            .where('recipients', arrayContains: userId)
            .limit(100) // Fetch more to ensure we have enough after filtering
            .get();
      } else {
        // No userId filter - just get recent circulars
        try {
          snapshot = await _firestore
              .collection('circulars')
              .orderBy('sentDate', descending: true)
              .limit(50)
              .get();
        } catch (e) {
          snapshot = await _firestore
              .collection('circulars')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get();
        }
      }

      List<Map<String, dynamic>> list = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          })
          .toList();

      // Filter by user if needed (client-side filtering)
      if (userId != null) {
        list = list.where((circular) {
          final recipients = circular['recipients'];
          if (recipients is List) {
            return recipients.contains(userId);
          }
          return false;
        }).toList();
      }

      // Client-side sort by most recent (createdAt first, then sentDate)
      list.sort((a, b) {
        int getTimestamp(Map<String, dynamic> circular) {
          // Try createdAt first, then sentDate
          final createdAt = circular['createdAt'];
          if (createdAt != null) {
            if (createdAt is Timestamp) {
              return createdAt.millisecondsSinceEpoch;
            }
            if (createdAt is Map && createdAt['seconds'] != null) {
              return (createdAt['seconds'] as int) * 1000;
            }
            if (createdAt is int) {
              return createdAt;
            }
          }
          
          final sentDate = circular['sentDate'];
          if (sentDate != null) {
            if (sentDate is Timestamp) {
              return sentDate.millisecondsSinceEpoch;
            }
            if (sentDate is Map && sentDate['seconds'] != null) {
              return (sentDate['seconds'] as int) * 1000;
            }
            if (sentDate is int) {
              return sentDate;
            }
          }
          return 0;
        }
        return getTimestamp(b) - getTimestamp(a); // Descending order
      });

      return list;
    } catch (e) {
      throw Exception('Failed to get circulars: ${e.toString()}');
    }
  }

  /// Stream circulars (real-time updates)
  Stream<List<Map<String, dynamic>>> streamCirculars({String? userId}) {
    Query query = _firestore.collection('circulars');
    
    if (userId != null) {
      // Use arrayContains without orderBy (no index available)
      // We'll sort client-side instead
      query = query
          .where('recipients', arrayContains: userId)
          .limit(100); // Fetch more to ensure we have enough after filtering
    } else {
      // Try sentDate first, fallback to createdAt
      try {
        query = query.orderBy('sentDate', descending: true).limit(50);
      } catch (e) {
        query = query.orderBy('createdAt', descending: true).limit(50);
      }
    }

    return query.snapshots().map((snapshot) {
      List<Map<String, dynamic>> list = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          })
          .toList();

      // Filter by user if needed (client-side filtering)
      if (userId != null) {
        list = list.where((circular) {
          final recipients = circular['recipients'];
          if (recipients is List) {
            return recipients.contains(userId);
          }
          return false;
        }).toList();
      }

      // Client-side sort by most recent
      list.sort((a, b) {
        int getTimestamp(Map<String, dynamic> circular) {
          // Try createdAt first, then sentDate
          final createdAt = circular['createdAt'];
          if (createdAt != null) {
            if (createdAt is Timestamp) {
              return createdAt.millisecondsSinceEpoch;
            }
            if (createdAt is Map && createdAt['seconds'] != null) {
              return (createdAt['seconds'] as int) * 1000;
            }
            if (createdAt is int) {
              return createdAt;
            }
          }
          
          final sentDate = circular['sentDate'];
          if (sentDate != null) {
            if (sentDate is Timestamp) {
              return sentDate.millisecondsSinceEpoch;
            }
            if (sentDate is Map && sentDate['seconds'] != null) {
              return (sentDate['seconds'] as int) * 1000;
            }
            if (sentDate is int) {
              return sentDate;
            }
          }
          return 0;
        }
        return getTimestamp(b) - getTimestamp(a); // Descending order
      });

      return list;
    });
  }

  /// Get circular by ID
  Future<Map<String, dynamic>?> getCircular(String circularId) async {
    try {
      final doc = await _firestore.collection('circulars').doc(circularId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      return {'id': doc.id, ...data};
    } catch (e) {
      throw Exception('Failed to get circular: ${e.toString()}');
    }
  }

  // ==================== EVENTS ====================

  /// Get events (optionally filtered by college)
  Future<List<Map<String, dynamic>>> getEvents({String? collegeId}) async {
    try {
      QuerySnapshot snapshot;
      
      // Use the available index: collegeId + createdAt
      if (collegeId != null) {
        snapshot = await _firestore
            .collection('events')
            .where('collegeId', isEqualTo: collegeId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get();
      } else {
        // No filter - try startDate first, fallback to createdAt
        try {
          snapshot = await _firestore
              .collection('events')
              .orderBy('startDate', descending: true)
              .limit(50)
              .get();
        } catch (e) {
          // Fallback to createdAt if startDate index doesn't exist
          snapshot = await _firestore
              .collection('events')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get();
        }
      }
      
      return snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              ...data,
              // Ensure images array exists
              'images': data['images'] ?? [],
              'status': data['status'] ?? 'upcoming',
            };
          })
          .toList();
    } catch (e) {
      throw Exception('Failed to get events: ${e.toString()}');
    }
  }

  /// Stream events (real-time updates)
  Stream<List<Map<String, dynamic>>> streamEvents({String? collegeId}) {
    Stream<QuerySnapshot> stream;
    
    // Use the available index: collegeId + createdAt
    if (collegeId != null) {
      stream = _firestore
          .collection('events')
          .where('collegeId', isEqualTo: collegeId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();
    } else {
      // No filter - use createdAt (most reliable)
      stream = _firestore
          .collection('events')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();
    }

    return stream.map((snapshot) {
      List<Map<String, dynamic>> list = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          })
          .toList();
      
      // Client-side sort by startDate if available (for better UX)
      list.sort((a, b) {
        int getTimestamp(Map<String, dynamic> event) {
          // Try startDate first, then createdAt
          final startDate = event['startDate'];
          if (startDate != null && startDate is String) {
            try {
              return DateTime.parse(startDate).millisecondsSinceEpoch;
            } catch (e) {
              // Ignore parse errors
            }
          }
          
          final createdAt = event['createdAt'];
          if (createdAt != null) {
            if (createdAt is Timestamp) {
              return createdAt.millisecondsSinceEpoch;
            }
            if (createdAt is Map && createdAt['seconds'] != null) {
              return (createdAt['seconds'] as int) * 1000;
            }
            if (createdAt is int) {
              return createdAt;
            }
          }
          return 0;
        }
        return getTimestamp(b) - getTimestamp(a); // Descending order
      });
      
      return list;
    });
  }

  /// Get event by ID
  Future<Map<String, dynamic>?> getEvent(String eventId) async {
    try {
      final doc = await _firestore.collection('events').doc(eventId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      return {'id': doc.id, ...data};
    } catch (e) {
      throw Exception('Failed to get event: ${e.toString()}');
    }
  }

  /// Add or update event
  Future<String> saveEvent(Map<String, dynamic> eventData, {String? eventId}) async {
    try {
      if (eventId != null) {
        await _firestore.collection('events').doc(eventId).update(eventData);
        return eventId;
      } else {
        final docRef = await _firestore.collection('events').add(eventData);
        return docRef.id;
      }
    } catch (e) {
      throw Exception('Failed to save event: ${e.toString()}');
    }
  }

  // ==================== NOTIFICATIONS/INVITATIONS ====================

  /// Get notifications/invitations for a user
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    try {
      // Use the available index: recipients + type + createdAt
      QuerySnapshot snapshot;
      try {
        snapshot = await _firestore
            .collection('notifications')
            .where('recipients', arrayContains: userId)
            .where('type', isEqualTo: 'invitation')
            .orderBy('createdAt', descending: true)
            .get();
      } catch (e) {
        // Fallback: try recipients + createdAt (without type filter)
        try {
          snapshot = await _firestore
              .collection('notifications')
              .where('recipients', arrayContains: userId)
              .orderBy('createdAt', descending: true)
              .get();
        } catch (e2) {
          // Last fallback: recipientId query
          snapshot = await _firestore
              .collection('notifications')
              .where('recipientId', isEqualTo: userId)
              .orderBy('createdAt', descending: true)
              .get();
        }
      }
      
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final responses = data['responses'] as Map<String, dynamic>? ?? {};
        final userResponse = responses[userId];
        String userStatus = 'pending';
        if (userResponse != null) {
          if (userResponse is Map) {
            userStatus = userResponse['status'] ?? 'pending';
          } else if (userResponse is String) {
            userStatus = userResponse;
          }
        }
        
        return {
          'id': doc.id,
          ...data,
          'status': userStatus,
        };
      }).toList();
    } catch (e) {
      throw Exception('Failed to get notifications: ${e.toString()}');
    }
  }

  /// Get all notifications for a user (not just invitations)
  Future<List<Map<String, dynamic>>> getAllNotifications(String userId) async {
    try {
      QuerySnapshot snapshot;
      try {
        // Try using recipients + createdAt index
        snapshot = await _firestore
            .collection('notifications')
            .where('recipients', arrayContains: userId)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get();
      } catch (e) {
        // Fallback: recipientId query
        try {
          snapshot = await _firestore
              .collection('notifications')
              .where('recipientId', isEqualTo: userId)
              .orderBy('createdAt', descending: true)
              .limit(100)
              .get();
        } catch (e2) {
          // Last fallback: get all and filter client-side
          snapshot = await _firestore
              .collection('notifications')
              .orderBy('createdAt', descending: true)
              .limit(200)
              .get();
        }
      }
      
      List<Map<String, dynamic>> notifications = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'id': doc.id, ...data};
      }).toList();
      
      // Filter by recipients if needed (client-side)
      notifications = notifications.where((notif) {
        final recipients = notif['recipients'];
        if (recipients is List) {
          return recipients.contains(userId);
        }
        final recipientId = notif['recipientId'];
        if (recipientId != null) {
          return recipientId == userId;
        }
        return false;
      }).toList();
      
      return notifications;
    } catch (e) {
      throw Exception('Failed to get notifications: ${e.toString()}');
    }
  }

  /// Stream all notifications (real-time updates)
  Stream<List<Map<String, dynamic>>> streamAllNotifications(String userId) {
    Stream<QuerySnapshot> stream;
    try {
      // Try using recipients + createdAt index
      stream = _firestore
          .collection('notifications')
          .where('recipients', arrayContains: userId)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots();
    } catch (e) {
      // Fallback: recipientId query
      try {
        stream = _firestore
            .collection('notifications')
            .where('recipientId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots();
      } catch (e2) {
        // Last fallback: get all and filter client-side
        stream = _firestore
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots();
      }
    }
    
    return stream.map((snapshot) {
      List<Map<String, dynamic>> notifications = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {'id': doc.id, ...data};
      }).toList();
      
      // Filter by recipients if needed (client-side)
      notifications = notifications.where((notif) {
        final recipients = notif['recipients'];
        if (recipients is List) {
          return recipients.contains(userId);
        }
        final recipientId = notif['recipientId'];
        if (recipientId != null) {
          return recipientId == userId;
        }
        return false;
      }).toList();
      
      return notifications;
    });
  }

  /// Stream notifications (real-time updates) - kept for backward compatibility
  Stream<List<Map<String, dynamic>>> streamNotifications(String userId) {
    return streamAllNotifications(userId);
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId, String userId) async {
    try {
      final docRef = _firestore.collection('notifications').doc(notificationId);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        throw Exception('Notification not found');
      }
      
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Notification data is null');
      }
      
      // Get current readBy array
      final readBy = List<String>.from(data['readBy'] ?? []);
      
      // Add user to readBy if not already present
      if (!readBy.contains(userId)) {
        readBy.add(userId);
        
        // Update the notification in Firebase
        await docRef.update({
          'readBy': readBy,
          'readAt': FieldValue.serverTimestamp(),
        });
        
        // Also set read to true if all recipients have read it
        final recipients = data['recipients'] as List?;
        if (recipients != null && recipients.length == readBy.length) {
          await docRef.update({
            'read': true,
          });
        }
      }
    } catch (e) {
      throw Exception('Failed to mark notification as read: ${e.toString()}');
    }
  }

  /// Get unread notification count
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final notifications = await getAllNotifications(userId);
      int count = 0;
      
      for (var notif in notifications) {
        final read = notif['read'];
        final readBy = notif['readBy'] as List?;
        
        // Check if notification is read
        bool isRead = false;
        if (read == true) {
          isRead = true;
        } else if (readBy != null && readBy.contains(userId)) {
          isRead = true;
        }
        
        if (!isRead) {
          count++;
        }
      }
      
      return count;
    } catch (e) {
      throw Exception('Failed to get unread count: ${e.toString()}');
    }
  }

  /// Update notification status
  Future<void> updateNotificationStatus(
    String notificationId,
    String status, // 'pending', 'accepted', 'declined'
  ) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update notification: ${e.toString()}');
    }
  }

  /// Update invitation response (for invitations with responses object)
  Future<void> updateInvitationResponse(
    String invitationId,
    String userId,
    String status, // 'accepted', 'declined'
  ) async {
    try {
      final docRef = _firestore.collection('notifications').doc(invitationId);
      final doc = await docRef.get();
      final data = doc.data() as Map<String, dynamic>?;
      final responses = Map<String, dynamic>.from(data?['responses'] as Map? ?? {});
      
      responses[userId] = {
        'status': status,
        'respondedAt': FieldValue.serverTimestamp(),
        'respondedBy': userId,
      };
      
      await docRef.update({
        'responses': responses,
      });
    } catch (e) {
      throw Exception('Failed to update invitation response: ${e.toString()}');
    }
  }

  // ==================== COLLEGES ====================

  /// Get all colleges
  Future<List<Map<String, dynamic>>> getColleges() async {
    try {
      final snapshot = await _firestore.collection('colleges').get();
      return snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          })
          .toList();
    } catch (e) {
      throw Exception('Failed to get colleges: ${e.toString()}');
    }
  }

  /// Get college by ID
  Future<Map<String, dynamic>?> getCollege(String collegeId) async {
    try {
      final doc = await _firestore.collection('colleges').doc(collegeId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      return {'id': doc.id, ...data};
    } catch (e) {
      throw Exception('Failed to get college: ${e.toString()}');
    }
  }

  // ==================== ENROLLMENT DATA ====================

  /// Get enrollment data submissions (optionally filtered by collegeId)
  Future<List<Map<String, dynamic>>> getEnrollmentSubmissions({String? collegeId, String? submittedBy}) async {
    try {
      Query query = _firestore.collection('enrollmentData');
      
      // Use the available index: collegeId + submittedAt
      if (collegeId != null) {
        query = query.where('collegeId', isEqualTo: collegeId).limit(50);
      } else if (submittedBy != null) {
        query = query.where('submittedBy', isEqualTo: submittedBy).limit(50);
      } else {
        query = query.limit(50);
      }

      final snapshot = await query.get();
      
      List<Map<String, dynamic>> submissions = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          })
          .toList();

      // Sort manually by submittedAt (descending)
      submissions.sort((a, b) {
        int getTimestamp(Map<String, dynamic> submission) {
          final submittedAt = submission['submittedAt'];
          if (submittedAt == null) return 0;
          if (submittedAt is Timestamp) {
            return submittedAt.millisecondsSinceEpoch;
          }
          if (submittedAt is Map && submittedAt['seconds'] != null) {
            return (submittedAt['seconds'] as int) * 1000;
          }
          if (submittedAt is int) {
            return submittedAt;
          }
          return 0;
        }
        return getTimestamp(b) - getTimestamp(a); // Descending order
      });

      return submissions;
    } catch (e) {
      throw Exception('Failed to get enrollment submissions: ${e.toString()}');
    }
  }

  /// Add enrollment data submission
  Future<String> addEnrollmentSubmission(Map<String, dynamic> submissionData) async {
    try {
      final docRef = await _firestore.collection('enrollmentData').add(submissionData);
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to add enrollment submission: $e');
    }
  }

  Future<void> updateEnrollmentSubmission(String submissionId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('enrollmentData').doc(submissionId).update(updates);
    } catch (e) {
      throw Exception('Failed to update enrollment submission: $e');
    }
  }

  // Tickets (Support/Feedback)
  Future<String> addTicket(Map<String, dynamic> ticketData) async {
    try {
      final docRef = await _firestore.collection('tickets').add(ticketData);
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to add ticket: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUserTickets(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('tickets')
          .where('userId', isEqualTo: userId)
          .get();

      final tickets = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Sort by createdAt in memory (newest first)
      tickets.sort((a, b) {
        final dateA = a['createdAt'] ?? '';
        final dateB = b['createdAt'] ?? '';
        return dateB.compareTo(dateA);
      });

      return tickets;
    } catch (e) {
      throw Exception('Failed to fetch user tickets: $e');
    }
  }

  // ==================== COURSES ====================
  
  /// Get all active courses with their streams
  Future<List<Map<String, dynamic>>> getCourses() async {
    try {
      final querySnapshot = await _firestore
          .collection('courses')
          .where('active', isEqualTo: true)
          .get();

      final courses = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'streams': List<String>.from(data['streams'] ?? []),
          'active': data['active'] ?? true,
        };
      }).toList();
      
      // Sort by name in memory
      courses.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      
      return courses;
    } catch (e) {
      throw Exception('Failed to fetch courses: $e');
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flclashx/common/app_localizations.dart';
import 'package:flclashx/common/print.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/plugins/vpn.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for showing subscription expiration notifications.
/// Shows notifications at exactly 3, 2, 1, and 0 days before expiration.
/// Each notification is shown only once per subscription period.
class SubscriptionNotificationService {
  static const String _prefsKeyPrefix = 'subscription_notified_';
  
  /// Days before expiration to show notifications
  /// 3 = 3 days left, 2 = 2 days left, 1 = 1 day left, 0 = expires today
  /// -1 is special: means subscription has expired
  static const List<int> notificationDays = [3, 2, 1, 0, -1];
  
  /// Check subscription and show notification if needed
  static Future<void> checkAndNotify(Profile profile) async {
    commonPrint.log('[SubscriptionNotification] checkAndNotify called for profile: ${profile.label}');
    
    if (!Platform.isAndroid) {
      commonPrint.log('[SubscriptionNotification] Not Android, skipping');
      return;
    }
    
    final subscriptionInfo = profile.subscriptionInfo;
    if (subscriptionInfo == null) {
      commonPrint.log('[SubscriptionNotification] No subscription info, skipping');
      return;
    }
    
    final expire = subscriptionInfo.expire;
    commonPrint.log('[SubscriptionNotification] expire timestamp: $expire');
    if (expire == 0) {
      commonPrint.log('[SubscriptionNotification] expire is 0, skipping');
      return;
    }
    
    // Calculate time until expiration
    final expireDate = DateTime.fromMillisecondsSinceEpoch(expire * 1000);
    final now = DateTime.now();
    final isExpired = expireDate.isBefore(now);
    final daysUntilExpire = expireDate.difference(now).inDays;
    
    commonPrint.log('[SubscriptionNotification] expireDate: $expireDate, now: $now, isExpired: $isExpired, daysUntilExpire: $daysUntilExpire');
    
    // Determine notification threshold
    // -1 means expired, 0 means expires today (but not yet expired), 1+ means days left
    final int notificationThreshold;
    if (isExpired) {
      notificationThreshold = -1; // Expired
    } else if (daysUntilExpire == 0) {
      notificationThreshold = 0; // Expires today
    } else {
      notificationThreshold = daysUntilExpire;
    }
    
    commonPrint.log('[SubscriptionNotification] notificationThreshold: $notificationThreshold');
    
    // Check if we should show notification for this threshold
    if (notificationDays.contains(notificationThreshold)) {
      commonPrint.log('[SubscriptionNotification] Threshold match! Showing notification');
      await _showNotificationIfNeeded(profile, notificationThreshold);
    } else {
      commonPrint.log('[SubscriptionNotification] Threshold ($notificationThreshold) not in notification list $notificationDays');
    }
  }
  
  static Future<void> _showNotificationIfNeeded(
    Profile profile,
    int notificationThreshold,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPrefsKey(profile.id, notificationThreshold);
    
    // Check if already notified for this threshold
    final lastNotifiedExpire = prefs.getInt(key);
    final currentExpire = profile.subscriptionInfo?.expire ?? 0;
    
    commonPrint.log('[SubscriptionNotification] key: $key, lastNotifiedExpire: $lastNotifiedExpire, currentExpire: $currentExpire');
    
    // If we already notified for this expire timestamp and threshold, skip
    if (lastNotifiedExpire == currentExpire) {
      commonPrint.log('[SubscriptionNotification] Already notified for this threshold, skipping');
      return;
    }
    
    // Get support URL for "Renew" button (optional)
    final supportUrl = profile.providerHeaders['support-url'] ?? '';
    commonPrint.log('[SubscriptionNotification] supportUrl: $supportUrl');
    
    // Get title from flclashx-servicename header or fallback to profile label
    String title = profile.label ?? profile.id;
    final svc = profile.providerHeaders['flclashx-servicename'];
    if (svc != null && svc.isNotEmpty) {
      try {
        final normalized = base64.normalize(svc);
        title = utf8.decode(base64.decode(normalized)).trim();
      } catch (_) {
        title = svc.trim();
      }
    }
    
    final String message;
    if (notificationThreshold < 0) {
      message = appLocalizations.subscriptionExpired;
    } else if (notificationThreshold == 0) {
      message = appLocalizations.subscriptionExpiresToday;
    } else {
      message = appLocalizations.subscriptionExpiresInDays(notificationThreshold.toString());
    }
    final actionLabel = appLocalizations.renew;
    
    commonPrint.log('[SubscriptionNotification] Calling vpn?.showSubscriptionNotification...');
    commonPrint.log('[SubscriptionNotification] vpn is null: ${vpn == null}');
    
    // Show notification (action button only if supportUrl is available)
    await vpn?.showSubscriptionNotification(
      title: title,
      message: message,
      actionLabel: supportUrl.isNotEmpty ? actionLabel : '',
      actionUrl: supportUrl,
    );
    
    commonPrint.log('[SubscriptionNotification] Notification sent, marking as notified');
    
    // Mark as notified
    await prefs.setInt(key, currentExpire);
  }
  
  static String _getPrefsKey(String profileId, int days) =>
      '$_prefsKeyPrefix${profileId}_${days}d';
  
  /// Reset notification state for a profile (call when subscription is renewed)
  static Future<void> resetNotifications(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final days in notificationDays) {
      final key = _getPrefsKey(profileId, days);
      await prefs.remove(key);
    }
  }
}

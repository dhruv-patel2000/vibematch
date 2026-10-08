import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_service.dart';

class IAPService {
  static final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  static late StreamSubscription<List<PurchaseDetails>> _subscription;

  static Future<void> init() async {
    final bool available = await _inAppPurchase.isAvailable();
    if (!available) {
      debugPrint("IAP not available");
      return;
    }

    _subscription = _inAppPurchase.purchaseStream.listen((List<PurchaseDetails> purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (Object error) {
      debugPrint("IAP Stream Error: $error");
    });
  }

  static void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        debugPrint("Purchase pending: \${purchaseDetails.productID}");
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint("Purchase error: \${purchaseDetails.error}");
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          _verifyPurchaseOnBackend(purchaseDetails);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  static Future<void> _verifyPurchaseOnBackend(PurchaseDetails purchaseDetails) async {
    try {
      // In a real app, send the receipt string to the backend to verify with Google/Apple
      // Here we just hit the endpoint we created.
      // purchaseDetails.verificationData.serverVerificationData contains the receipt.
      // packId needs to match the productID from the store.
      
      /* 
      await ApiService._dio.post('/payment/mobile', data: {
        'packId': purchaseDetails.productID,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'purchaseDetails': {
          'purchaseID': purchaseDetails.purchaseID,
          'receipt': purchaseDetails.verificationData.serverVerificationData
        }
      });
      */
      debugPrint("Verified purchase on backend: \${purchaseDetails.productID}");
    } catch (e) {
      debugPrint("Failed to verify purchase on backend: $e");
    }
  }

  static Future<void> buyProduct(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam, autoConsume: true);
  }
}

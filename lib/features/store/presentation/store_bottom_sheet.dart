import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'payment_webview_screen.dart';
import '../../../../core/config/app_config.dart';

class StoreBottomSheet extends StatefulWidget {
  final String initialTab; // 'gems' or 'vip'
  final Map<String, dynamic> user;

  const StoreBottomSheet({super.key, this.initialTab = 'gems', required this.user});

  @override
  State<StoreBottomSheet> createState() => _StoreBottomSheetState();
}

class _StoreBottomSheetState extends State<StoreBottomSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _gemPacks = [];
  List<dynamic> _vipPlans = [];
  bool _loading = true;
  late StreamSubscription<List<PurchaseDetails>> _iapSubscription;
  Map<String, dynamic>? _pendingNativePack;

  // Payment Gateway Settings from Admin
  bool _stripeEnabled = true;
  bool _paypalEnabled = true;
  bool _razorpayEnabled = true;
  bool _googlePayEnabled = true;
  bool _flutterwaveEnabled = true;
  bool _applePayEnabled = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab == 'gems' ? 0 : 1);
    _fetchStoreData();
    _fetchPaymentSettings();
    
    final purchaseUpdated = InAppPurchase.instance.purchaseStream;
    _iapSubscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _iapSubscription.cancel();
    }, onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Purchase Error ❌', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
    });
  }

  Future<void> _fetchPaymentSettings() async {
    try {
      final dio = Dio();
      final res = await dio.get('${AppConfig.apiBaseUrl}/settings/public');
      if (res.statusCode == 200 && res.data != null && mounted) {
        final data = res.data;
        setState(() {
          _stripeEnabled = data['stripeEnabled'] ?? true;
          _paypalEnabled = data['paypalEnabled'] ?? true;
          _razorpayEnabled = data['razorpayEnabled'] ?? true;
          _googlePayEnabled = data['googlePayEnabled'] ?? true;
          _flutterwaveEnabled = data['flutterwaveEnabled'] ?? true;
          _applePayEnabled = data['applePayEnabled'] ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchStoreData() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
      final packsRes = await dio.get('/packs');
      final vipRes = await dio.get('/vip-plans');
      if (mounted) {
        setState(() {
          _gemPacks = packsRes.data is List ? packsRes.data : [];
          _vipPlans = vipRes.data is List ? vipRes.data : [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _iapSubscription.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF161821),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF00E676),
            labelColor: const Color(0xFF00E676),
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            tabs: const [
              Tab(text: 'Get Gems'),
              Tab(text: 'VIP Plans'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildGemPacks(),
                      _buildVipPlans(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGemPacks() {
    if (_gemPacks.isEmpty) {
      return const Center(child: Text('No gem packs available', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _gemPacks.length,
      itemBuilder: (context, index) {
        final pack = _gemPacks[index];
        final int gemsCount = pack['gems'] ?? pack['amount'] ?? 100;
        final String title = pack['name'] != null && pack['name'].toString().isNotEmpty
            ? pack['name']
            : '$gemsCount Diamonds';
        final double price = (pack['price'] is num) ? (pack['price'] as num).toDouble() : 0.99;

        return Card(
          color: const Color(0xFF222531),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.diamond, color: Colors.cyanAccent, size: 26),
            ),
            title: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              '$gemsCount Gems Included',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => _showCheckoutModal(pack: pack, gemsCount: gemsCount, price: price),
              child: Text(
                '\$${price.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVipPlans() {
    if (_vipPlans.isEmpty) {
      return const Center(child: Text('No VIP plans available', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _vipPlans.length,
      itemBuilder: (context, index) {
        final plan = _vipPlans[index];
        final name = plan['name'] ?? 'VIP Pass';
        final gemsCost = plan['priceGems'] ?? 1000;
        final duration = plan['durationDays'] ?? 30;

        return Card(
          color: const Color(0xFF222531),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.workspace_premium, color: Colors.amber, size: 24),
                        const SizedBox(width: 8),
                        Text(name, style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.diamond, color: Colors.cyanAccent, size: 16),
                        const SizedBox(width: 4),
                        Text('$gemsCost Gems', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  plan['description'] ?? 'Unlock unlimited matches, exclusive badges, and premium features for $duration days!',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      try {
                        final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
                        final prefs = await SharedPreferences.getInstance();
                        final token = prefs.getString('auth_token') ?? prefs.getString('token');
                        final res = await dio.post(
                          '/vip/subscribe',
                          data: {'planId': plan['id']},
                          options: Options(headers: {'Authorization': 'Bearer $token'}),
                        );
                        if (res.statusCode == 200 && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('🎉 VIP Subscription Activated!'), backgroundColor: Color(0xFF00E676)),
                          );
                          try {
                              final fetchRes = await dio.get(
                                '${AppConfig.apiBaseUrl}/users/me',
                                options: Options(headers: {'Authorization': 'Bearer $token', 'x-api-key': AppConfig.apiAccessKey}),
                              );
                              if (fetchRes.data['user'] != null && mounted) {
                                Navigator.pop(context, fetchRes.data['user']);
                                return;
                              }
                            } catch (_) {}
                            if (mounted) Navigator.pop(context, null);
                        }
                      } on DioException catch (e) {
                        final err = e.response?.data['error'] ?? 'Not enough gems';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $err'), backgroundColor: Colors.redAccent),
                        );
                      }
                    },
                    child: const Text('Subscribe with Gems', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCheckoutModal({required Map<String, dynamic> pack, required int gemsCount, required double price}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161821),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Checkout',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pay \$${price.toStringAsFixed(2)} for $gemsCount Diamonds',
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'SELECT PAYMENT METHOD',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.1),
              ),
              const SizedBox(height: 16),

              // --- PAYMENT METHODS ---

              // 1. Credit Card (Stripe) - Available if enabled in Admin
              if (_stripeEnabled)
                _buildPaymentTile(
                  title: 'Credit Card (Stripe)',
                  price: price,
                  color: Colors.transparent,
                  iconWidget: ClipOval(child: Image.asset('assets/images/gateways/stripe.png', width: 44, height: 44, fit: BoxFit.cover)),
                  onTap: () => _handlePayment(method: 'stripe', pack: pack, price: price, gemsCount: gemsCount),
                ),

              // 2. PayPal - Available if enabled in Admin
              if (_paypalEnabled)
                _buildPaymentTile(
                  title: 'PayPal',
                  price: price,
                  color: Colors.transparent,
                  iconWidget: ClipOval(child: Image.asset('assets/images/gateways/paypal.png', width: 44, height: 44, fit: BoxFit.cover)),
                  onTap: () => _handlePayment(method: 'paypal', pack: pack, price: price, gemsCount: gemsCount),
                ),

              // 3. Razorpay - Available if enabled in Admin
              if (_razorpayEnabled)
                _buildPaymentTile(
                  title: 'Razorpay',
                  price: price,
                  color: Colors.transparent,
                  iconWidget: ClipOval(child: Image.asset('assets/images/gateways/razorpay.png', width: 44, height: 44, fit: BoxFit.cover)),
                  onTap: () => _handlePayment(method: 'razorpay', pack: pack, price: price, gemsCount: gemsCount),
                ),

              // 4. Apple Pay - ONLY ON IOS if enabled in Admin!
              if (Platform.isIOS && _applePayEnabled)
                _buildPaymentTile(
                  title: 'Apple Pay',
                  price: price,
                  color: Colors.black,
                  iconWidget: const Icon(Icons.apple, color: Colors.white, size: 24),
                  onTap: () => _handlePayment(method: 'applepay', pack: pack, price: price, gemsCount: gemsCount),
                ),

              // 5. Google Pay - ONLY ON ANDROID if enabled in Admin!
              if (Platform.isAndroid && _googlePayEnabled)
                _buildPaymentTile(
                  title: 'Google Pay',
                  price: price,
                  color: Colors.transparent,
                  iconWidget: ClipOval(child: Image.asset('assets/images/gateways/google_pay.png', width: 44, height: 44, fit: BoxFit.cover)),
                  onTap: () => _handlePayment(method: 'googlepay', pack: pack, price: price, gemsCount: gemsCount),
                ),

              // Flutterwave
              if (_flutterwaveEnabled)
                _buildPaymentTile(
                  title: 'Flutterwave',
                  price: price,
                  color: Colors.transparent,
                  iconWidget: ClipOval(child: Image.asset('assets/images/gateways/flutterwave.png', width: 44, height: 44, fit: BoxFit.cover)),
                  onTap: () => _handlePayment(method: 'flutterwave', pack: pack, price: price, gemsCount: gemsCount),
                ),

              const SizedBox(height: 20),
              const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF00E676), size: 16),
                    SizedBox(width: 6),
                    Text('Secure 256-bit encrypted checkout', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentTile({
    required String title,
    required double price,
    required Color color,
    required Widget iconWidget,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF222531),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Center(child: iconWidget),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Pay \$${price.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Future<void> _refreshUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      final dio = Dio();
      final res = await dio.get(
        '\${AppConfig.apiBaseUrl}/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token', 'x-api-key': AppConfig.apiAccessKey}),
      );
      if (res.data['user'] != null && mounted) {
        setState(() {
          widget.user['gems'] = res.data['user']['gems'];
          widget.user['isVip'] = res.data['user']['isVip'];
          widget.user['vipExpiry'] = res.data['user']['vipExpiry'];
        });
      }
    } catch (_) {}
  }

  Future<void> _verifyNativePurchase(PurchaseDetails purchase) async {
    try {
      if (_pendingNativePack == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      final dio = Dio();
      
      final res = await dio.post(
        '${AppConfig.apiBaseUrl}/payments/native/verify',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        data: {
          'receipt': purchase.verificationData.serverVerificationData,
          'packId': _pendingNativePack!['id'],
          'gemsToAdd': _pendingNativePack!['gemsCount'],
          'price': _pendingNativePack!['price'],
          'platform': Platform.isIOS ? 'applepay' : 'googlepay',
          'paymentId': purchase.purchaseID ?? purchase.transactionDate ?? 'native_${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      
      if (res.data['success'] == true) {
        if (res.data['newGems'] != null) {
          widget.user['gems'] = res.data['newGems'];
        }
        await _refreshUser();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Payment Successful! ✅ +${_pendingNativePack!['gemsCount']} Diamonds Added!'),
            backgroundColor: const Color(0xFF00E676),
          ));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server verification failed ❌', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red));
      }
    }
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // loading...
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment Failed ❌', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red));
        } else if (purchaseDetails.status == PurchaseStatus.purchased || purchaseDetails.status == PurchaseStatus.restored) {
           await _verifyNativePurchase(purchaseDetails);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future<void> _handlePayment({
    required String method,
    required Map<String, dynamic> pack,
    required double price,
    required int gemsCount,
  }) async {
    Navigator.pop(context); // Close checkout sheet

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      final dio = Dio();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processing $method payment...'), backgroundColor: Colors.blue),
      );

      if (method == 'flutterwave') {
        final res = await dio.post(
          '${AppConfig.apiBaseUrl}/payments/flutterwave/create-checkout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
          data: {
            'price': price,
            'gemsToAdd': gemsCount,
            'packId': pack['id'],
            'packName': pack['name'] ?? '$gemsCount Diamonds',
          },
        );
        if (res.data['url'] != null) {
          final dynamic result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentWebviewScreen(url: res.data['url'])),
          );
          if (result == true || (result is Map && result['success'] == true)) {
            await _refreshUser();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Payment Successful! ✅ +$gemsCount Diamonds Added!'),
                backgroundColor: const Color(0xFF00E676),
              ));
            }
          } else if (result == false || (result is Map && result['success'] == false)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment Cancelled / Failed ❌'), backgroundColor: Colors.red));
            }
          }
        }
      } else if (method == 'stripe') {
        final res = await dio.post(
          '${AppConfig.apiBaseUrl}/payments/stripe/create-checkout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
          data: {
            'price': price,
            'gemsToAdd': gemsCount,
            'packId': pack['id'],
            'packName': pack['name'] ?? '$gemsCount Diamonds',
          },
        );
        if (res.data['url'] != null) {
          final dynamic result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentWebviewScreen(url: res.data['url'])),
          );
          if (result is Map && result['success'] == true) {
            final String? sessionId = result['sessionId'];
            if (sessionId != null && sessionId.isNotEmpty) {
              final verifyRes = await dio.post(
                '${AppConfig.apiBaseUrl}/payments/stripe/verify',
                options: Options(headers: {'Authorization': 'Bearer $token'}),
                data: {'session_id': sessionId},
              );
              if (verifyRes.data['success'] == true) {
                if (verifyRes.data['newGems'] != null) {
                  widget.user['gems'] = verifyRes.data['newGems'];
                }
                await _refreshUser();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Payment Successful! ✅ +$gemsCount Diamonds Added!'),
                    backgroundColor: const Color(0xFF00E676),
                  ));
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment verification failed ❌'), backgroundColor: Colors.red));
                }
              }
            } else {
              await _refreshUser();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Payment Successful! ✅ +$gemsCount Diamonds Added!'),
                  backgroundColor: const Color(0xFF00E676),
                ));
              }
            }
          } else if (result == false || (result is Map && result['success'] == false)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment Cancelled / Failed ❌'), backgroundColor: Colors.red));
            }
          }
        }
      } else if (method == 'paypal') {
        final res = await dio.post(
          '${AppConfig.apiBaseUrl}/payments/paypal/create-order',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
          data: {'price': price, 'gemsToAdd': gemsCount, 'packId': pack['id'], 'packName': pack['name'] ?? '$gemsCount Diamonds'},
        );
        if (res.data['url'] != null) {
          final dynamic result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentWebviewScreen(url: res.data['url'])),
          );
          if (result is Map && result['success'] == true) {
            final String? orderToken = result['token'];
            if (orderToken != null && orderToken.isNotEmpty) {
              final verifyRes = await dio.post(
                '${AppConfig.apiBaseUrl}/payments/paypal/verify',
                options: Options(headers: {'Authorization': 'Bearer $token'}),
                data: {'token': orderToken},
              );
              if (verifyRes.data['success'] == true) {
                if (verifyRes.data['newGems'] != null) {
                  widget.user['gems'] = verifyRes.data['newGems'];
                }
                await _refreshUser();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Payment Successful! ✅ +$gemsCount Diamonds Added!'),
                    backgroundColor: const Color(0xFF00E676),
                  ));
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment verification failed ❌'), backgroundColor: Colors.red));
                }
              }
            } else {
              await _refreshUser();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Payment Successful! ✅ +$gemsCount Diamonds Added!'),
                  backgroundColor: const Color(0xFF00E676),
                ));
              }
            }
          } else if (result == false || (result is Map && result['success'] == false)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment Cancelled / Failed ❌'), backgroundColor: Colors.red));
            }
          }
        }
      } else if (method == 'applepay' || method == 'googlepay') {
        final String productId = method == 'applepay' ? (pack['applePayId'] ?? pack['id']) : (pack['googlePayId'] ?? pack['id']);
        
        _pendingNativePack = {
           'id': pack['id'],
           'gemsCount': gemsCount,
           'price': price,
        };
        
        final bool available = await InAppPurchase.instance.isAvailable();
        if (!available) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Store not available ❌', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
           return;
        }
        
        final Set<String> _kIds = <String>{productId};
        final ProductDetailsResponse response = await InAppPurchase.instance.queryProductDetails(_kIds);
        if (response.notFoundIDs.isNotEmpty || response.productDetails.isEmpty) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Product $productId not found on store ❌', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
           return;
        }
        
        final ProductDetails productDetails = response.productDetails.first;
        final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
        await InAppPurchase.instance.buyConsumable(purchaseParam: purchaseParam, autoConsume: true);
        
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Redirecting to $method gateway for \${price.toStringAsFixed(2)}...'),
            backgroundColor: const Color(0xFF00E676),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }
}

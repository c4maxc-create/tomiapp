import 'package:flutter/material.dart';
import '../widgets.dart';

class WalletOffer {
  const WalletOffer(this.base, this.bonus, this.price);
  final int base, bonus;
  final String price;
  int get total => base + bonus;
}

const walletOffers = [
  WalletOffer(350, 80, '0.49'),
  WalletOffer(650, 160, '0.99'),
  WalletOffer(1850, 350, '2.99'),
  WalletOffer(3100, 600, '4.99'),
  WalletOffer(12000, 2000, '12.99'),
  WalletOffer(59000, 12000, '59.99'),
];

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});
  static void open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const WalletPage()),
  );
  String amount(int n) => n >= 10000 ? '${n ~/ 1000}K' : '$n';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المحفظة')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xff223f49), Color(0xff29233f)],
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 32,
                    color: TomiColors.accent,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'عروض الشحن',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'هذه العروض للعرض فقط حاليًا. الشراء راح يتوفر مستقبلًا.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, c) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: walletOffers.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, i) {
                  final o = walletOffers[i];
                  return Semantics(
                    button: true,
                    label:
                        '${o.base} كوينز مع ${o.bonus} إضافة مقابل ${o.price} دولار، عرض فقط',
                    child: Material(
                      key: ValueKey('wallet-offer-$i'),
                      color: const Color(0xff17313f),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('الشراء قريبًا'),
                            content: const Text(
                              'بالمستقبل تگدر تشتري؛ حاليًا هذه الباقات للعرض فقط، وما راح ينخصم منك أي مبلغ.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d),
                                child: const Text('تمام'),
                              ),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              const Expanded(
                                flex: 2,
                                child: Icon(
                                  Icons.monetization_on_rounded,
                                  color: Color(0xffffd46f),
                                  size: 24,
                                ),
                              ),
                              Expanded(
                                child: FittedBox(
                                  child: Text(
                                    amount(o.base),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: FittedBox(
                                  child: Text(
                                    '+ ${amount(o.bonus)} إضافة',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: TomiColors.accent,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: FittedBox(
                                  child: Text(
                                    '\$${o.price}',
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xffffd46f),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'الأسعار بالدولار الأمريكي • لا توجد عملية شراء أو إضافة رصيد في هذه النسخة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TomiColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

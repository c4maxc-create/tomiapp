package com.tomi.tomi_app;

public final class MobilePolicyTest {
    private static void check(boolean value,String scenario) { if (!value) throw new AssertionError(scenario); }
    public static void main(String[] args) {
        long now=1000000;
        check(MobilePolicy.incoming(now,now+35000,0,true,"alice","session2","alice","session2"),"valid incoming call");
        check(!MobilePolicy.incoming(now,now,0,true,"alice","session2","alice","session2"),"expired ring");
        check(!MobilePolicy.incoming(now,now+40001,0,true,"alice","session2","alice","session2"),"unbounded lifetime");
        check(!MobilePolicy.incoming(now,now+35000,now+120000,true,"alice","session2","alice","session2"),"cancel before incoming must not resurrect");
        check(!MobilePolicy.incoming(now,now+35000,0,true,"alice","session1","alice","session2"),"same account previous session");
        check(!MobilePolicy.incoming(now,now+35000,0,true,"alice","session2","bob","session2"),"account switch");
        check(!MobilePolicy.incoming(now,now+35000,0,false,"alice","session2","alice","session2"),"disabled notifications");
        check(!MobilePolicy.incoming(now,now+35000,0,true,"alice",null,"alice",null),"missing binding");
        check(MobilePolicy.action("immutable-pending-intent-secret","immutable-pending-intent-secret"),"owned notification action");
        check(!MobilePolicy.action("forged", "immutable-pending-intent-secret"),"external intent injection");
        check(!MobilePolicy.action(null,null),"uninitialized secret");
        System.out.println("PASS: 11 native notification policy scenarios.");
    }
}

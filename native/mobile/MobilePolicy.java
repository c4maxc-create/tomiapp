package com.tomi.tomi_app;

/** Pure predicates shared by the native presentation path and JVM tests. */
public final class MobilePolicy {
    public static boolean incoming(long now,long expires,long closedUntil,boolean enabled,
        String account,String binding,String currentAccount,String currentBinding) {
        return enabled && account!=null && binding!=null && account.equals(currentAccount)
            && binding.equals(currentBinding) && expires>now && expires-now<=40000 && closedUntil<=now;
    }
    public static boolean update(boolean enabled,String account,String currentAccount,String type,String id) {
        return enabled && account!=null && account.equals(currentAccount) && ("chat".equals(type)||"activity".equals(type)||"notice".equals(type))
            && id!=null && id.matches("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$");
    }
    public static boolean action(String nonce,String secret) {
        return secret!=null && secret.equals(nonce);
    }
}

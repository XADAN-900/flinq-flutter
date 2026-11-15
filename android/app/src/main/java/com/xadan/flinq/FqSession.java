package com.xadan.flinq;

import android.content.Context;
import android.content.SharedPreferences;

/** Giriş yapmış kullanıcı ve bildirim tercihleri (Flutter tarafı köprüyle kaydeder). */
final class FqSession {
    final String uid;
    final boolean enabled;
    final boolean sound;
    final boolean preview;

    private FqSession(SharedPreferences p) {
        uid = p.getString("uid", null);
        enabled = p.getBoolean("enabled", true);
        sound = p.getBoolean("sound", true);
        preview = p.getBoolean("preview", true);
    }

    boolean valid() {
        return uid != null && !uid.isEmpty();
    }

    private static SharedPreferences p(Context c) {
        return c.getApplicationContext().getSharedPreferences("fq_native_session", Context.MODE_PRIVATE);
    }

    static FqSession load(Context c) {
        return new FqSession(p(c));
    }

    static void save(Context c, String uid, boolean enabled, boolean sound, boolean preview) {
        p(c).edit().putString("uid", uid).putBoolean("enabled", enabled)
                .putBoolean("sound", sound).putBoolean("preview", preview).apply();
    }

    static void clear(Context c) {
        p(c).edit().clear().apply();
    }
}

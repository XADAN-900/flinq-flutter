package com.xadan.flinq;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.text.Html;

import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;
import com.google.firebase.database.ChildEventListener;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.FirebaseDatabase;
import com.google.firebase.database.Query;
import com.google.firebase.database.ValueEventListener;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Uygulama kapalıyken de (servis çalıştığı sürece) kullanıcının bildirimlerini ve DM'lerini
 * Firebase'den canlı dinler. Kimlik doğrulaması Firebase Auth'un cihazdaki oturumuyla yapılır.
 */
final class FqWatcher {

    static final String DB_URL = "https://flinq-8e74c-default-rtdb.europe-west1.firebasedatabase.app";

    private static FqWatcher instance;

    static synchronized FqWatcher get(Context c) {
        if (instance == null) instance = new FqWatcher(c.getApplicationContext());
        return instance;
    }

    private final Context ctx;
    private final Handler main = new Handler(Looper.getMainLooper());
    private FirebaseDatabase db;
    private String uid;
    private long startedAt;

    private Query notifQuery;
    private ChildEventListener notifListener;
    private Query chatsQuery;
    private ChildEventListener chatsListener;

    private final Set<String> seen = new HashSet<>();
    private final Map<String, Long> unread = new HashMap<>();
    private final Map<String, String> names = new HashMap<>();
    /** Engellediğim kişiler: onlardan bildirim gösterilmez. */
    private final Set<String> blocked = new HashSet<>();
    private com.google.firebase.database.DatabaseReference blockedRef;
    private ValueEventListener blockedListener;

    private FqWatcher(Context c) {
        ctx = c;
    }

    void refresh() {
        main.post(this::doRefresh);
    }

    void shutdown() {
        main.post(this::doStop);
    }

    private void ensureApp() {
        if (FirebaseApp.getApps(ctx).isEmpty()) {
            // Flutter tarafındaki FirebaseOptions ile birebir aynı (yoksa duplicate-app hatası).
            FirebaseOptions o = new FirebaseOptions.Builder()
                    .setApplicationId("1:40261522799:web:79a7a32902ee7231e7049a")
                    .setApiKey("AIzaSyDdSWxFYZ8YsHFAk-NMpvVPNTdf-QyWvx4")
                    .setGcmSenderId("40261522799")
                    .setProjectId("flinq-8e74c")
                    .setDatabaseUrl(DB_URL)
                    .setStorageBucket("flinq-8e74c.appspot.com")
                    .build();
            FirebaseApp.initializeApp(ctx, o);
        }
        if (db == null) db = FirebaseDatabase.getInstance(DB_URL);
    }

    private void doRefresh() {
        FqSession s = FqSession.load(ctx);
        if (!s.valid()) {
            doStop();
            return;
        }
        try {
            ensureApp();
        } catch (Exception e) {
            return;
        }
        FirebaseUser u = null;
        try {
            u = FirebaseAuth.getInstance().getCurrentUser();
        } catch (Exception ignored) {
        }
        if (u == null || !u.getUid().equals(s.uid)) {
            doStop();
            return;
        }
        if (s.uid.equals(uid)) return; // zaten dinliyor
        doStop();
        uid = s.uid;
        startedAt = System.currentTimeMillis();
        watchBlocked();
        watchNotifications();
        watchChats();
    }

    private void doStop() {
        try {
            if (notifQuery != null && notifListener != null) notifQuery.removeEventListener(notifListener);
            if (chatsQuery != null && chatsListener != null) chatsQuery.removeEventListener(chatsListener);
        } catch (Exception ignored) {
        }
        try {
            if (blockedRef != null && blockedListener != null) blockedRef.removeEventListener(blockedListener);
        } catch (Exception ignored) {
        }
        blockedRef = null;
        blockedListener = null;
        blocked.clear();
        notifQuery = null;
        notifListener = null;
        chatsQuery = null;
        chatsListener = null;
        uid = null;
        unread.clear();
    }

    private abstract static class Adapter implements ChildEventListener {
        @Override public void onChildAdded(DataSnapshot s, String p) { }
        @Override public void onChildChanged(DataSnapshot s, String p) { }
        @Override public void onChildRemoved(DataSnapshot s) { }
        @Override public void onChildMoved(DataSnapshot s, String p) { }
        @Override public void onCancelled(DatabaseError e) { }
    }

    private void watchBlocked() {
        blockedRef = db.getReference("users").child(uid).child("blocked");
        blockedListener = new ValueEventListener() {
            @Override
            public void onDataChange(DataSnapshot s) {
                blocked.clear();
                for (DataSnapshot c : s.getChildren()) {
                    if (c.getKey() != null) blocked.add(c.getKey());
                }
            }

            @Override
            public void onCancelled(DatabaseError e) {
            }
        };
        blockedRef.addValueEventListener(blockedListener);
    }

    // ---------- beğeni / yorum / takip / yanıt / etiket ----------

    private void watchNotifications() {
        notifQuery = db.getReference("notifications").child(uid).orderByKey().limitToLast(20);
        notifListener = new Adapter() {
            @Override
            public void onChildAdded(DataSnapshot s, String p) {
                try {
                    String id = s.getKey();
                    if (id == null || !seen.add(id)) return;
                    Boolean read = s.child("read").getValue(Boolean.class);
                    Long time = s.child("time").getValue(Long.class);
                    if (read != null && read) return;
                    // Servis başlamadan önceki eski bildirimleri tekrar gösterme
                    if (time == null || time < startedAt - 60_000) return;
                    if (MainActivity.visible) return;
                    String from = s.child("from").getValue(String.class);
                    if (from != null && blocked.contains(from)) return;
                    String msg = s.child("message").getValue(String.class);
                    FqNotify.showActivity(ctx, id, plain(msg));
                } catch (Exception ignored) {
                }
            }
        };
        notifQuery.addChildEventListener(notifListener);
    }

    // ---------- DM ----------

    private void watchChats() {
        chatsQuery = db.getReference("userChats").child(uid);
        chatsListener = new Adapter() {
            @Override
            public void onChildAdded(DataSnapshot s, String p) {
                Long n = s.child("unread").getValue(Long.class);
                if (s.getKey() != null) unread.put(s.getKey(), n == null ? 0L : n);
                // Servisten sonra açılan yeni sohbetin ilk mesajı
                Long ts = s.child("lastTs").getValue(Long.class);
                if (n != null && n > 0 && ts != null && ts > startedAt) onChat(s);
            }

            @Override
            public void onChildChanged(DataSnapshot s, String p) {
                String key = s.getKey();
                if (key == null) return;
                Long n = s.child("unread").getValue(Long.class);
                long now = n == null ? 0L : n;
                Long prev = unread.get(key);
                unread.put(key, now);
                if (now > (prev == null ? 0L : prev)) onChat(s);
            }
        };
        chatsQuery.addChildEventListener(chatsListener);
    }

    private void onChat(final DataSnapshot s) {
        try {
            if (MainActivity.visible) return;
            final String chatId = s.getKey();
            final String other = s.child("with").getValue(String.class);
            final String lastFrom = s.child("lastFrom").getValue(String.class);
            final String text = s.child("lastText").getValue(String.class);
            if (chatId == null || other == null || other.equals(uid) || uid.equals(lastFrom)) return;
            if (blocked.contains(other)) return;
            String cached = names.get(other);
            if (cached != null) {
                FqNotify.showDm(ctx, chatId, other, cached, text == null ? "Yeni mesaj" : text);
                return;
            }
            db.getReference("users").child(other).child("username")
                    .addListenerForSingleValueEvent(new ValueEventListener() {
                        @Override
                        public void onDataChange(DataSnapshot d) {
                            String name = d.getValue(String.class);
                            if (name == null || name.isEmpty()) name = "FlinQ";
                            names.put(other, name);
                            FqNotify.showDm(ctx, chatId, other, name, text == null ? "Yeni mesaj" : text);
                        }

                        @Override
                        public void onCancelled(DatabaseError e) {
                            FqNotify.showDm(ctx, chatId, other, "FlinQ", text == null ? "Yeni mesaj" : text);
                        }
                    });
        } catch (Exception ignored) {
        }
    }

    private static String plain(String html) {
        if (html == null) return "Yeni bildirim";
        try {
            CharSequence cs = Build.VERSION.SDK_INT >= 24
                    ? Html.fromHtml(html, Html.FROM_HTML_MODE_LEGACY)
                    : Html.fromHtml(html);
            String t = cs.toString().trim();
            return t.isEmpty() ? "Yeni bildirim" : t;
        } catch (Exception e) {
            return html.replaceAll("<[^>]*>", "");
        }
    }
}

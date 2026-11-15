package com.xadan.flinq;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;

/** FlinQ bildirimleri: etkinlik (beğeni, yorum, takip...), DM ve arka plan servisi. */
final class FqNotify {
    static final String CH_ACTIVITY = "fq_activity";
    static final String CH_QUIET = "fq_activity_silent";
    static final String CH_SERVICE = "fq_service";
    static final int ID_SERVICE = 1;

    static final String ACTION_OPEN_NOTIF = "com.xadan.flinq.OPEN_NOTIF";
    static final String ACTION_OPEN_DM = "com.xadan.flinq.OPEN_DM";
    static final String EXTRA_ID = "fq_id";

    private static final int COLOR = 0xFFFF3D71;
    private static final int PI_FLAGS = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;

    private FqNotify() {
    }

    private static NotificationManager nm(Context c) {
        return (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    }

    private static Notification.Builder builder(Context c, String ch) {
        if (Build.VERSION.SDK_INT >= 26) return new Notification.Builder(c, ch);
        return new Notification.Builder(c);
    }

    static Uri sound(Context c) {
        return Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + c.getPackageName() + "/" + R.raw.flinq_notify);
    }

    static void createChannels(Context c) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = nm(c);
        AudioAttributes aa = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        if (nm.getNotificationChannel(CH_ACTIVITY) == null) {
            NotificationChannel a = new NotificationChannel(CH_ACTIVITY, "Etkinlik", NotificationManager.IMPORTANCE_HIGH);
            a.setDescription("Beğeni, yorum, takip, yanıt, etiket ve mesaj bildirimleri");
            a.setSound(sound(c), aa);
            a.enableVibration(true);
            a.setShowBadge(true);
            nm.createNotificationChannel(a);
        }
        if (nm.getNotificationChannel(CH_QUIET) == null) {
            NotificationChannel q = new NotificationChannel(CH_QUIET, "Etkinlik (sessiz)", NotificationManager.IMPORTANCE_DEFAULT);
            q.setSound(null, null);
            q.enableVibration(false);
            nm.createNotificationChannel(q);
        }
        if (nm.getNotificationChannel(CH_SERVICE) == null) {
            NotificationChannel s = new NotificationChannel(CH_SERVICE, "Arka plan bağlantısı", NotificationManager.IMPORTANCE_LOW);
            s.setShowBadge(false);
            s.setSound(null, null);
            nm.createNotificationChannel(s);
        }
    }

    private static PendingIntent open(Context c, String action, String id, int req) {
        Intent i = new Intent(c, MainActivity.class)
                .setAction(action)
                .putExtra(EXTRA_ID, id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(c, req, i, PI_FLAGS);
    }

    static Notification service(Context c) {
        Intent i = new Intent(c, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        Notification.Builder b = builder(c, CH_SERVICE)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("FlinQ")
                .setContentText("Bildirimler için bağlı")
                .setContentIntent(PendingIntent.getActivity(c, 0, i, PI_FLAGS))
                .setOngoing(true)
                .setColor(COLOR)
                .setVisibility(Notification.VISIBILITY_SECRET);
        if (Build.VERSION.SDK_INT < 26) b.setPriority(Notification.PRIORITY_MIN);
        return b.build();
    }

    private static void show(Context c, int nid, String title, String text, PendingIntent pi) {
        FqSession s = FqSession.load(c);
        if (!s.enabled) return;
        String ch = s.sound ? CH_ACTIVITY : CH_QUIET;
        Notification pub = builder(c, ch)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("FlinQ")
                .setContentText("Yeni bir bildirimin var")
                .setColor(COLOR)
                .build();
        Notification.Builder b = builder(c, ch)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setColor(COLOR)
                .setShowWhen(true)
                .setGroup("flinq_activity")
                .setVisibility(s.preview ? Notification.VISIBILITY_PUBLIC : Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(pub);
        if (Build.VERSION.SDK_INT < 26) {
            b.setPriority(Notification.PRIORITY_HIGH);
            if (s.sound) b.setSound(sound(c));
        }
        try {
            nm(c).notify(nid, b.build());
        } catch (Exception ignored) {
        }
    }

    static void showActivity(Context c, String notifId, String text) {
        int nid = 2000 + Math.abs(notifId.hashCode() % 100000);
        show(c, nid, "FlinQ", text, open(c, ACTION_OPEN_NOTIF, notifId, nid));
    }

    static void showDm(Context c, String chatId, String otherUid, String title, String text) {
        int nid = 200000 + Math.abs(chatId.hashCode() % 100000);
        show(c, nid, title, text, open(c, ACTION_OPEN_DM, otherUid, nid));
    }

    static void clearAll(Context c) {
        try {
            NotificationManager nm = nm(c);
            nm.cancelAll();
        } catch (Exception ignored) {
        }
    }
}

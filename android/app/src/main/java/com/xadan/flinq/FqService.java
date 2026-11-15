package com.xadan.flinq;

import android.app.Notification;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/** Süreci canlı tutar ("FlinQ · Bildirimler için bağlı") ve FqWatcher ile Firebase'i dinler. */
public class FqService extends Service {

    static void ensureRunning(Context c) {
        try {
            Intent i = new Intent(c, FqService.class);
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i);
            else c.startService(i);
        } catch (Exception ignored) {
        }
    }

    static void stop(Context c) {
        try {
            c.stopService(new Intent(c, FqService.class));
        } catch (Exception ignored) {
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        FqNotify.createChannels(this);
        Notification n = FqNotify.service(this);
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(FqNotify.ID_SERVICE, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING);
            } else if (Build.VERSION.SDK_INT >= 29) {
                startForeground(FqNotify.ID_SERVICE, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
            } else {
                startForeground(FqNotify.ID_SERVICE, n);
            }
        } catch (Exception e) {
            stopSelf();
            return START_NOT_STICKY;
        }
        FqWatcher.get(this).refresh();
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        FqWatcher.get(this).shutdown();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}

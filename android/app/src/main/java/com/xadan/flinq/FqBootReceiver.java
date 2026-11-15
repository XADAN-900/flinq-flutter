package com.xadan.flinq;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Telefon yeniden başlayınca / uygulama güncellenince bildirim dinlemeyi geri getirir. */
public class FqBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (FqSession.load(context).valid()) {
            FqNotify.createChannels(context);
            FqService.ensureRunning(context);
        }
    }
}

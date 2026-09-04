package com.kotlinsun.lumiandroid

import android.app.Application
import com.kotlinsun.lumiandroid.service.LumiNotifications
import com.meta.wearable.dat.core.Wearables

class LumiApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        LumiNotifications.createChannels(this)
        Wearables.initialize(this)
    }
}

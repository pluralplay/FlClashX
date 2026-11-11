package com.follow.clashx

import android.app.Application
import android.content.Context
import com.follow.clashx.common.GlobalState

class FlClashApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}

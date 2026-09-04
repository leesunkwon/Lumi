package com.kotlinsun.lumiandroid.service

import android.app.Activity
import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.camera.addStream
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.StreamState
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Session
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import kotlinx.coroutines.flow.first

class GlassesController {
    private var session: Session? = null
    private var stream: Stream? = null

    fun startRegistration(activity: Activity): Result<Unit> = runCatching {
        Wearables.startRegistration(activity).getOrElse { error ->
            throw GlassesException(error.description)
        }
    }

    suspend fun capturePhoto(): ByteArray {
        val activeStream = ensureStream()
        activeStream.state.first { it == StreamState.STREAMING }
        return activeStream.capturePhoto().fold(
            onSuccess = { it.data },
            onFailure = { error, _ -> throw GlassesException(error.description) },
        )
    }

    fun stop() {
        stream?.stop()
        session?.stop()
        stream = null
        session = null
    }

    private fun ensureStream(): Stream {
        stream?.let { return it }
        val createdSession = Wearables.createSession(AutoDeviceSelector()).getOrElse { error ->
            throw GlassesException(error.description)
        }
        createdSession.start()
        val createdStream = createdSession.addStream(
            StreamConfiguration(videoQuality = VideoQuality.MEDIUM, frameRate = 24),
        ).getOrElse { error -> throw GlassesException(error.description) }
        createdStream.start().getOrElse { error -> throw GlassesException(error.description) }
        session = createdSession
        stream = createdStream
        return createdStream
    }
}

class GlassesException(message: String) : IllegalStateException(message)

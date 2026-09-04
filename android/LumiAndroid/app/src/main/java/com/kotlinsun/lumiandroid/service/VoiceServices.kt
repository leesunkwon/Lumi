package com.kotlinsun.lumiandroid.service

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import java.io.File
import java.util.UUID

class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null

    fun start() {
        check(recorder == null) { "이미 녹음 중이에요." }
        val file = File(context.cacheDir, "voice-${UUID.randomUUID()}.m4a")
        val newRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        newRecorder.apply {
            setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioEncodingBitRate(64_000)
            setAudioSamplingRate(24_000)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
        recorder = newRecorder
        outputFile = file
    }

    fun stop(): ByteArray {
        val activeRecorder = recorder ?: throw IllegalStateException("녹음 중이 아니에요.")
        val file = outputFile ?: throw IllegalStateException("녹음 파일을 찾을 수 없어요.")
        try {
            activeRecorder.stop()
            return file.readBytes()
        } finally {
            activeRecorder.reset()
            activeRecorder.release()
            recorder = null
            outputFile = null
            file.delete()
        }
    }

    fun cancel() {
        runCatching { recorder?.stop() }
        recorder?.release()
        outputFile?.delete()
        recorder = null
        outputFile = null
    }
}

class SpeechPlayer(private val context: Context) {
    private var track: AudioTrack? = null
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private var previousCommunicationDevice: android.media.AudioDeviceInfo? = null

    fun play(speech: SynthesizedSpeech) {
        stop()
        selectBluetoothCommunicationDevice()
        val channelMask = if (speech.channelCount > 1) AudioFormat.CHANNEL_OUT_STEREO else AudioFormat.CHANNEL_OUT_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minBuffer = AudioTrack.getMinBufferSize(speech.sampleRate, channelMask, encoding).coerceAtLeast(speech.bytes.size)
        val audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(speech.sampleRate).setChannelMask(channelMask).setEncoding(encoding).build())
            .setBufferSizeInBytes(minBuffer)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        audioTrack.write(speech.bytes, 0, speech.bytes.size)
        audioTrack.play()
        track = audioTrack
    }

    fun stop() {
        track?.let { current ->
            runCatching { current.pause() }
            current.flush()
            current.release()
        }
        track = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION") audioManager.stopBluetoothSco()
        }
        previousCommunicationDevice = null
    }

    private fun selectBluetoothCommunicationDevice() {
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            previousCommunicationDevice = audioManager.communicationDevice
            audioManager.availableCommunicationDevices
                .firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == android.media.AudioDeviceInfo.TYPE_BLE_HEADSET }
                ?.let(audioManager::setCommunicationDevice)
        } else {
            @Suppress("DEPRECATION") audioManager.startBluetoothSco()
        }
    }
}

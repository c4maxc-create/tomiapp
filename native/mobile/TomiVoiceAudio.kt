package com.tomi.tomi_app

import android.content.Context
import android.media.AudioManager
import android.os.Build

/** Owns the transition back from communication audio to a voice-note session. */
object TomiVoiceAudio {
    @JvmStatic
    fun prepare(context: Context, recording: Boolean): String {
        if (TomiAudioService.active()) return if (recording) "busy" else "playing"
        val audio = context.getSystemService(AudioManager::class.java) ?: return "unavailable"
        audio.mode = AudioManager.MODE_NORMAL
        if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice()
        @Suppress("DEPRECATION")
        audio.isSpeakerphoneOn = false
        if (recording) {
            audio.isMicrophoneMute = false
            if (audio.isMicrophoneMute) return "muted"
        }
        return "ready"
    }
}

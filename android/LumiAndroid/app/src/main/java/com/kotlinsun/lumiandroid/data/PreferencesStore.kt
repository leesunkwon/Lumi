package com.kotlinsun.lumiandroid.data

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

data class LumiPreferences(
    val confirmBeforeAction: Boolean = true,
    val keyboardInputEnabled: Boolean = false,
    val responseTone: ResponseTone = ResponseTone.JARVIS,
)

class PreferencesStore(context: Context) {
    private val store = PreferenceDataStoreFactory.create {
        context.applicationContext.preferencesDataStoreFile("lumi_preferences")
    }

    val preferences: Flow<LumiPreferences> = store.data.map { values ->
        LumiPreferences(
            confirmBeforeAction = values[CONFIRM_BEFORE_ACTION] ?: true,
            keyboardInputEnabled = values[KEYBOARD_INPUT] ?: false,
            responseTone = values[RESPONSE_TONE]?.let { runCatching { ResponseTone.valueOf(it) }.getOrNull() }
                ?: ResponseTone.JARVIS,
        )
    }

    suspend fun update(transform: (LumiPreferences) -> LumiPreferences) {
        store.edit { values ->
            val current = LumiPreferences(
                confirmBeforeAction = values[CONFIRM_BEFORE_ACTION] ?: true,
                keyboardInputEnabled = values[KEYBOARD_INPUT] ?: false,
                responseTone = values[RESPONSE_TONE]?.let { runCatching { ResponseTone.valueOf(it) }.getOrNull() }
                    ?: ResponseTone.JARVIS,
            )
            val next = transform(current)
            values[CONFIRM_BEFORE_ACTION] = next.confirmBeforeAction
            values[KEYBOARD_INPUT] = next.keyboardInputEnabled
            values[RESPONSE_TONE] = next.responseTone.name
        }
    }

    private companion object {
        val CONFIRM_BEFORE_ACTION = booleanPreferencesKey("confirm_before_action")
        val KEYBOARD_INPUT = booleanPreferencesKey("keyboard_input")
        val RESPONSE_TONE = stringPreferencesKey("response_tone")
    }
}

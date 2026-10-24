package com.example.self_control.persistence

import android.content.Context
import android.content.SharedPreferences

class SharedPreferencesBlockingStore(
    private val prefs: SharedPreferences
) : BlockingPersistenceStore {

    companion object {
        const val PREFS_NAME = "self_control_blocking_prefs"
        const val KEY_BLOCKED_PACKAGES = "blocked_packages"
        const val KEY_SESSION_START = "active_session_start"
        const val KEY_SESSION_END = "active_session_end"
        const val KEY_SESSION_STATUS = "active_session_status"
        const val KEY_PENDING_BOOT_SYNCS = "pending_boot_syncs"
        const val KEY_UNLOCK_PREFIX = "temp_unlock_"

        fun create(context: Context): SharedPreferencesBlockingStore {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return SharedPreferencesBlockingStore(prefs)
        }
    }

    override fun getBlockedPackages(): Set<String> {
        return prefs.getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()
    }

    override fun saveBlockedPackages(packages: Collection<String>) {
        prefs.edit()
            .putStringSet(KEY_BLOCKED_PACKAGES, packages.filter { it.isNotBlank() }.toSet())
            .apply()
    }

    override fun getActiveSession(): SessionData? {
        val start = prefs.getLong(KEY_SESSION_START, 0L)
        val end = prefs.getLong(KEY_SESSION_END, 0L)
        val status = prefs.getString(KEY_SESSION_STATUS, null) ?: return null
        return SessionData(start, end, status)
    }

    override fun saveActiveSession(startEpochMs: Long, endEpochMs: Long, status: String) {
        prefs.edit()
            .putLong(KEY_SESSION_START, startEpochMs)
            .putLong(KEY_SESSION_END, endEpochMs)
            .putString(KEY_SESSION_STATUS, status)
            .apply()
    }

    override fun updateSessionStatus(status: String) {
        prefs.edit().putString(KEY_SESSION_STATUS, status).apply()
    }

    override fun recordPendingBootSync(timestampMs: Long) {
        val current = prefs.getStringSet(KEY_PENDING_BOOT_SYNCS, emptySet())?.toMutableSet() ?: mutableSetOf()
        current.add(timestampMs.toString())
        prefs.edit().putStringSet(KEY_PENDING_BOOT_SYNCS, current).apply()
    }

    override fun consumePendingBootSyncs(): List<Long> {
        val current = prefs.getStringSet(KEY_PENDING_BOOT_SYNCS, emptySet()) ?: emptySet()
        if (current.isEmpty()) return emptyList()
        prefs.edit().remove(KEY_PENDING_BOOT_SYNCS).apply()
        return current.mapNotNull { it.toLongOrNull() }.sorted()
    }

    override fun getSavedTemporaryUnlocks(): Map<String, Long> {
        val result = mutableMapOf<String, Long>()
        for ((key, value) in prefs.all) {
            if (key.startsWith(KEY_UNLOCK_PREFIX) && value is Long) {
                val pkg = key.removePrefix(KEY_UNLOCK_PREFIX)
                result[pkg] = value
            }
        }
        return result
    }

    override fun saveTemporaryUnlock(packageName: String, expirationMs: Long) {
        prefs.edit().putLong("$KEY_UNLOCK_PREFIX$packageName", expirationMs).apply()
    }

    override fun removeTemporaryUnlock(packageName: String) {
        prefs.edit().remove("$KEY_UNLOCK_PREFIX$packageName").apply()
    }

    override fun clearExpiredTemporaryUnlocks(nowMs: Long) {
        val editor = prefs.edit()
        for ((key, value) in prefs.all) {
            if (key.startsWith(KEY_UNLOCK_PREFIX) && value is Long && value <= nowMs) {
                editor.remove(key)
            }
        }
        editor.apply()
    }
}

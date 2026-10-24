package com.example.self_control.persistence

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

class SharedPreferencesBlockingStore(
    private val prefs: SharedPreferences
) : BlockingPersistenceStore {

    companion object {
        const val PREFS_NAME = "self_control_blocking_prefs"
        const val KEY_BLOCKED_PACKAGES = "blocked_packages"
        const val KEY_SESSION_START = "active_session_start"
        const val KEY_SESSION_END = "active_session_end"
        const val KEY_SESSION_STATUS = "active_session_status"
        const val KEY_SESSION_JSON = "active_session_json"
        const val KEY_PENDING_BOOT_SYNCS = "pending_boot_syncs"
        const val KEY_UNLOCK_PREFIX = "temp_unlock_"
        const val KEY_UNLOCKS_JSON = "temporary_unlocks_json"

        fun create(context: Context): SharedPreferencesBlockingStore {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return SharedPreferencesBlockingStore(prefs)
        }
    }

    override fun getBlockedPackages(): Set<String> {
        return try {
            prefs.getStringSet(KEY_BLOCKED_PACKAGES, emptySet()) ?: emptySet()
        } catch (_: Exception) {
            emptySet()
        }
    }

    override fun saveBlockedPackages(packages: Collection<String>) {
        try {
            prefs.edit()
                .putStringSet(KEY_BLOCKED_PACKAGES, packages.filter { it.isNotBlank() }.toSet())
                .apply()
        } catch (_: Exception) {
        }
    }

    override fun getActiveSession(): SessionData? {
        return try {
            val jsonStr = prefs.getString(KEY_SESSION_JSON, null)
            if (jsonStr != null) {
                val json = JSONObject(jsonStr)
                SessionData(
                    startEpochMs = json.optLong("startEpochMs", 0L),
                    endEpochMs = json.optLong("endEpochMs", 0L),
                    status = json.optString("status", "")
                )
            } else {
                val start = prefs.getLong(KEY_SESSION_START, 0L)
                val end = prefs.getLong(KEY_SESSION_END, 0L)
                val status = prefs.getString(KEY_SESSION_STATUS, null) ?: return null
                SessionData(start, end, status)
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun saveActiveSession(startEpochMs: Long, endEpochMs: Long, status: String) {
        try {
            prefs.edit()
                .putLong(KEY_SESSION_START, startEpochMs)
                .putLong(KEY_SESSION_END, endEpochMs)
                .putString(KEY_SESSION_STATUS, status)
                .apply()
        } catch (_: Exception) {
        }
    }

    override fun updateSessionStatus(status: String) {
        try {
            prefs.edit().putString(KEY_SESSION_STATUS, status).apply()
        } catch (_: Exception) {
        }
    }

    @Synchronized
    override fun recordPendingBootSync(timestampMs: Long) {
        try {
            val current = prefs.getStringSet(KEY_PENDING_BOOT_SYNCS, emptySet())?.toMutableSet() ?: mutableSetOf()
            current.add(timestampMs.toString())
            prefs.edit().putStringSet(KEY_PENDING_BOOT_SYNCS, current).apply()
        } catch (_: Exception) {
        }
    }

    @Synchronized
    override fun consumePendingBootSyncs(): List<Long> {
        return try {
            val current = prefs.getStringSet(KEY_PENDING_BOOT_SYNCS, emptySet()) ?: emptySet()
            if (current.isEmpty()) return emptyList()
            prefs.edit().remove(KEY_PENDING_BOOT_SYNCS).apply()
            current.mapNotNull { it.toLongOrNull() }.sorted()
        } catch (_: Exception) {
            emptyList()
        }
    }

    override fun getSavedTemporaryUnlocks(): Map<String, Long> {
        val result = mutableMapOf<String, Long>()
        return try {
            val jsonStr = prefs.getString(KEY_UNLOCKS_JSON, null)
            if (jsonStr != null) {
                val json = JSONObject(jsonStr)
                for (key in json.keys()) {
                    result[key] = json.optLong(key, 0L)
                }
            }
            for ((key, value) in prefs.all) {
                if (key.startsWith(KEY_UNLOCK_PREFIX)) {
                    val expiration = when (value) {
                        is Long -> value
                        is Number -> value.toLong()
                        is String -> {
                            try {
                                if (value.trim().startsWith("{")) {
                                    val obj = JSONObject(value)
                                    obj.optLong("expirationMs", 0L)
                                } else {
                                    value.toLongOrNull()
                                }
                            } catch (_: Exception) {
                                value.toLongOrNull()
                            }
                        }
                        else -> null
                    }
                    if (expiration != null && expiration > 0L) {
                        val pkg = key.removePrefix(KEY_UNLOCK_PREFIX)
                        result[pkg] = expiration
                    }
                }
            }
            result
        } catch (_: Exception) {
            result
        }
    }

    override fun saveTemporaryUnlock(packageName: String, expirationMs: Long) {
        try {
            prefs.edit().putLong("$KEY_UNLOCK_PREFIX$packageName", expirationMs).apply()
        } catch (_: Exception) {
        }
    }

    override fun removeTemporaryUnlock(packageName: String) {
        try {
            prefs.edit().remove("$KEY_UNLOCK_PREFIX$packageName").apply()
        } catch (_: Exception) {
        }
    }

    override fun clearExpiredTemporaryUnlocks(nowMs: Long) {
        try {
            val editor = prefs.edit()
            for ((key, value) in prefs.all) {
                if (key.startsWith(KEY_UNLOCK_PREFIX)) {
                    val expiration = when (value) {
                        is Long -> value
                        is Number -> value.toLong()
                        is String -> value.toLongOrNull()
                        else -> null
                    }
                    if (expiration != null && expiration <= nowMs) {
                        editor.remove(key)
                    }
                }
            }
            editor.apply()
        } catch (_: Exception) {
        }
    }
}

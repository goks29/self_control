package com.example.self_control.blocking

sealed class BlockingDecision {
    abstract val packageName: String
    abstract val reason: String
    abstract val shouldBlock: Boolean
    abstract val status: String
    abstract val timestamp: Long

    data class Allow(
        override val packageName: String,
        override val reason: String = REASON_NOT_RESTRICTED,
        override val timestamp: Long = System.currentTimeMillis()
    ) : BlockingDecision() {
        override val shouldBlock: Boolean = false
        override val status: String = STATUS_NOT_REQUIRED

        companion object {
            const val REASON_EMPTY_PACKAGE = "empty_package"
            const val REASON_SELF_PACKAGE = "self_package"
            const val REASON_NOT_RESTRICTED = "app_not_in_blocked_list"
            const val REASON_TEMPORARY_UNLOCK = "temporary_unlock_active"
            const val STATUS_NOT_REQUIRED = "not_required"
        }
    }

    data class Block(
        override val packageName: String,
        override val reason: String = REASON_POLICY_RESTRICTED,
        override val timestamp: Long = System.currentTimeMillis()
    ) : BlockingDecision() {
        override val shouldBlock: Boolean = true
        override val status: String = STATUS_ATTEMPTED

        companion object {
            const val REASON_POLICY_RESTRICTED = "restricted_package"
            const val STATUS_ATTEMPTED = "attempted"
            const val STATUS_CONFIRMED = "confirmed"
            const val STATUS_FAILED = "failed"
        }
    }
}

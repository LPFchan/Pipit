package com.immogen.pipit.onboarding

import com.immogen.core.KeyStoreManager

class OnboardingGate private constructor(
    private val keyStoreManager: KeyStoreManager
) {
    constructor() : this(KeyStoreManager())

    fun hasAnyProvisionedKey(): Boolean {
        for (slotId in 0 until SLOT_COUNT) {
            if (keyStoreManager.loadKey(slotId) != null) {
                return true
            }
        }
        return false
    }

    companion object {
        const val SLOT_COUNT = 4
    }
}
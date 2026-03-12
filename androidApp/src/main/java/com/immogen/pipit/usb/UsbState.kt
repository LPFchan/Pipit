package com.immogen.pipit.usb

sealed class UsbState {
    object Disconnected : UsbState()
    object Connecting : UsbState()
    data class Connected(val deviceType: DeviceType) : UsbState()
    data class Error(val message: String) : UsbState()
    
    // Operation states
    data class Flashing(val progressPercent: Int) : UsbState()
    object FlashingSuccess : UsbState()
    object PinChangeSuccess : UsbState()
    object ProvisioningSuccess : UsbState()
}

enum class DeviceType {
    GUILLEMOT_MASS_STORAGE,
    GUILLEMOT_SERIAL,
    UGUISU_SERIAL,
    UNKNOWN
}

# /// script
# requires-python = ">=3.10"
# dependencies = ["pyusb>=1.2"]
# ///
"""Check the gateware USB full-speed device (prototypes/usb-fs-device) from a real Linux host.

The device on the ULX3S's US2 connector should enumerate as 1209:0001 (the pid.codes test ID),
class 0xFF, with one configuration, one interface and bulk endpoints 0x01 (OUT) and 0x81 (IN) of
8 bytes; endpoint 1 loops back what it receives.

    uv run host/usb_check.py            # descriptors, then 8 loopback rounds

Needs read/write access to the device (udev rule in BRINGUP.md) and libusb. Untested: written
before the board arrived, from the descriptor bytes in usb-fs-device/usb_sie.ml.
"""
import sys

import usb.core
import usb.util

VID, PID = 0x1209, 0x0001


def main() -> int:
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        print(f"no device {VID:04x}:{PID:04x}; check lsusb, dmesg, the US2 cable and LED 4 (configured)")
        return 1
    print(f"found {VID:04x}:{PID:04x} bus {dev.bus} address {dev.address} speed {dev.speed} "
          f"(expect 2 = full speed with pyusb's libusb1 backend)")
    ok = True

    def expect(name, got, want):
        nonlocal ok
        good = got == want
        ok &= good
        print(f"  {name:28s} {got!r:12} {'ok' if good else f'expected {want!r}'}")

    expect("bcdUSB", dev.bcdUSB, 0x0200)
    expect("bDeviceClass", dev.bDeviceClass, 0xFF)
    expect("bMaxPacketSize0", dev.bMaxPacketSize0, 8)
    expect("bNumConfigurations", dev.bNumConfigurations, 1)
    try:
        dev.set_configuration(1)
    except usb.core.USBError as e:
        print(f"  set_configuration(1) failed: {e}")
        return 1
    cfg = dev.get_active_configuration()
    intf = cfg[(0, 0)]
    eps = sorted((e.bEndpointAddress, usb.util.endpoint_type(e.bmAttributes), e.wMaxPacketSize) for e in intf)
    expect("endpoints", eps, [(0x01, usb.util.ENDPOINT_TYPE_BULK, 8), (0x81, usb.util.ENDPOINT_TYPE_BULK, 8)])

    for i in range(8):
        data = bytes((i * 37 + k * 11) & 0xFF for k in range(8))
        n = dev.write(0x01, data, timeout=1000)
        back = bytes(dev.read(0x81, 8, timeout=1000))
        good = n == 8 and back == data
        ok &= good
        print(f"  loopback {i}: sent {data.hex()} got {back.hex()} {'ok' if good else 'MISMATCH'}")
    print("USB PASS" if ok else "USB FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

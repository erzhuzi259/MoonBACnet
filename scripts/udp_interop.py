"""Real loopback UDP against independent BACpypes3; no physical device claims."""
from pathlib import Path
import socket
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "_local/oracle"))
from bacpypes3.apdu import (APDU, APCISequence, ConfirmedRequestPDU, ReadPropertyRequest,
                           WritePropertyRequest, WhoIsRequest, SubscribeCOVRequest, WhoHasRequest, SimpleAckPDU)
from bacpypes3.pdu import PDU
from bacpypes3.npdu import NPDU
from bacpypes3.ipv4.bvll import OriginalUnicastNPDU, LPDU
from bacpypes3.primitivedata import Real, Null
from bacpypes3.basetypes import WhoHasObject


def main():
    exe = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "_build/native/debug/build/cmd/udp/udp.exe"
    process = subprocess.Popen([str(exe.resolve()), "0", "20"], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    watchdog = threading.Timer(20, process.kill)
    watchdog.start()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    sock.settimeout(3)
    counter = 0
    notifications = []
    try:
        ready = process.stdout.readline().strip()
        assert ready.startswith("READY "), (ready, process.poll())
        address = ("127.0.0.1", int(ready.split()[1]))

        def decode(packet):
            link = LPDU.decode(PDU(packet))
            network = NPDU.decode(PDU(link.pduData))
            raw = APDU.decode(PDU(network.pduData))
            return APCISequence.decode(raw) if raw.apduType in (0, 1, 3, 5) else raw

        def exchange(request):
            nonlocal counter
            counter += 1
            if isinstance(request, ConfirmedRequestPDU):
                request.apduInvokeID = counter
                request.apduMaxResp = 5
                request.apduMaxSegs = 0
                request.apduSA = False
            request.apduSeg = False
            request.apduMor = False
            network = NPDU(bytes(request.encode().encode().pduData))
            network.pduExpectingReply = isinstance(request, ConfirmedRequestPDU)
            packet = bytes(OriginalUnicastNPDU(bytes(network.encode().pduData)).encode().pduData)
            sock.sendto(packet, address)
            while True:
                data, peer = sock.recvfrom(65536)
                assert peer == address
                response = decode(data)
                if response.apduType == 1 and getattr(response, "apduService", None) == 2:
                    notifications.append(response)
                    continue
                if isinstance(request, ConfirmedRequestPDU):
                    assert response.apduInvokeID == counter
                return response

        def write(value, priority):
            return exchange(WritePropertyRequest(objectIdentifier=("analogValue", 1),
                propertyIdentifier="presentValue", propertyValue=value, priority=priority))

        def read():
            result = exchange(ReadPropertyRequest(objectIdentifier=("analogValue", 1),
                                                  propertyIdentifier="presentValue"))
            return float(result.propertyValue.cast_out(Real))

        assert int(exchange(WhoIsRequest()).iAmDeviceIdentifier[1]) == 42
        assert write(Real(20), 12).apduType == 2
        assert write(Real(24), 8).apduType == 2
        assert read() == 24
        assert write(Null(()), 8).apduType == 2
        assert read() == 20
        result = exchange(ReadPropertyRequest(objectIdentifier=("analogValue", 1), propertyIdentifier=9999))
        assert result.apduType == 5
        # Malformed datagram must not terminate the host or corrupt the device.
        sock.sendto(b"bad", address)
        assert read() == 20
        assert exchange(SubscribeCOVRequest(subscriberProcessIdentifier=7,
            monitoredObjectIdentifier=("analogValue", 1), issueConfirmedNotifications=False,
            lifetime=30)).apduType == 2
        assert write(Real(21), 12).apduType == 2
        assert exchange(SubscribeCOVRequest(subscriberProcessIdentifier=7,
            monitoredObjectIdentifier=("analogValue", 1))).apduType == 2
        assert notifications, "COV initial/changed notifications missing over UDP"
        assert exchange(SubscribeCOVRequest(subscriberProcessIdentifier=8,
            monitoredObjectIdentifier=("analogValue",1),issueConfirmedNotifications=True,
            lifetime=30)).apduType == 2
        sock.settimeout(5)
        original, peer = sock.recvfrom(65536)
        initial = decode(original)
        assert peer == address and initial.apduType == 0 and initial.apduService == 1
        assert initial.subscriberProcessIdentifier == 8
        repeated, peer = sock.recvfrom(65536)
        assert peer == address and repeated == original, "COV retry must retain invoke and payload"
        def acknowledge(notification):
            ack = SimpleAckPDU(1, notification.apduInvokeID)
            network = NPDU(bytes(ack.encode().pduData))
            sock.sendto(bytes(OriginalUnicastNPDU(bytes(network.encode().pduData)).encode().pduData),address)
        acknowledge(initial)
        assert write(Real(22),12).apduType == 2
        changed, peer = sock.recvfrom(65536)
        notification = decode(changed)
        assert peer == address and notification.apduType == 0
        assert notification.apduInvokeID != initial.apduInvokeID
        acknowledge(notification)
        assert exchange(SubscribeCOVRequest(subscriberProcessIdentifier=8,
            monitoredObjectIdentifier=("analogValue",1))).apduType == 2
        found = exchange(WhoHasRequest(object=WhoHasObject(objectName="setpoint")))
        assert found.objectIdentifier[1] == 1
        network = NPDU(bytes.fromhex("0c057700010c"))
        network.pduExpectingReply = True
        sock.sendto(bytes(OriginalUnicastNPDU(bytes(network.encode().pduData)).encode().pduData),address)
        aborted, peer = sock.recvfrom(65536)
        abort = decode(aborted)
        assert peer == address and abort.apduType == 7 and abort.apduInvokeID == 0x77 and int(abort.apduAbortRejectReason) == 4
        assert int(exchange(WhoIsRequest()).iAmDeviceIdentifier[1]) == 42
        assert process.wait(timeout=5) == 0, process.stderr.read()
    finally:
        sock.close()
        watchdog.cancel()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
    print("PASS: 20 loopback UDP inputs, discovery, priority release, property errors, both COV modes, exact confirmed retry/ACK, cancellation and segmentation Abort/recovery")


if __name__ == "__main__":
    main()

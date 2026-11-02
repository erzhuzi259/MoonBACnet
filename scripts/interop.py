"""Independent typed BACpypes3 vectors and persistent MoonBit device-host exchange.

No BACpypes source is copied into the library. This is an original test harness.
The transport is newline-delimited hex datagrams over stdio, not a UDP network.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "_local/oracle"))
from bacpypes3.apdu import (
    APDU, APCISequence, ConfirmedRequestPDU, ComplexAckPDU,
    ReadPropertyRequest, ReadPropertyACK, WritePropertyRequest,
    ReadPropertyMultipleRequest, SubscribeCOVRequest,
    UnconfirmedCOVNotificationRequest, WhoIsRequest, IAmRequest,
)
from bacpypes3.basetypes import ReadAccessSpecification, PropertyReference, PropertyValue
from bacpypes3.constructeddata import ArrayOf
from bacpypes3.primitivedata import (
    Null, Boolean, Unsigned, Integer, Real, Double, OctetString,
    CharacterString, BitString, Enumerated, Date, Time, ObjectIdentifier, TagList,
)
from bacpypes3.pdu import PDU
from bacpypes3.npdu import NPDU
from bacpypes3.ipv4.bvll import OriginalUnicastNPDU, OriginalBroadcastNPDU, LPDU
from importlib.metadata import version

assert version("bacpypes3") == "0.0.110"
executable_dir = ROOT / "_build/native/debug/build/cmd/main"
exe = next((executable_dir / name for name in ("main.exe", "main")
            if (executable_dir / name).is_file()), executable_dir / "main.exe")
if not exe.exists():
    raise SystemExit("Build first: moon build --target native --deny-warn")

def header(q, invoke=7):
    q.apduInvokeID = invoke
    q.apduSeg = False
    q.apduMor = False
    if isinstance(q, ConfirmedRequestPDU):
        q.apduMaxResp = 5
        q.apduMaxSegs = 0
        q.apduSA = False
    return q

def wire(q):
    return bytes(q.encode().encode().pduData)

def moon(mode, data):
    with tempfile.TemporaryDirectory(prefix="moonbacnet-interop-") as folder:
        source, target = Path(folder)/"input.bin", Path(folder)/"new-output.bin"
        source.write_bytes(data)
        subprocess.run([str(exe),mode,str(source),str(target)],check=True,capture_output=True,timeout=10)
        return target.read_bytes()

primitives = [Null(()),Boolean(False),Boolean(True),Unsigned(0),Unsigned(256),Unsigned(4294967295),
    Integer(-2147483648),Integer(-129),Integer(127),Real(-0.0),Real(23.5),Double(-0.0),Double(1e100),
    OctetString(b"\x00\xff"),CharacterString("月 🌙\ufeff\x00"),BitString([1,0,1]),BitString([]),
    Enumerated(65536),Date((126,10,29,4)),Date((255,13,32,255)),
    Time((12,30,59,99)),Time((255,255,255,255)),ObjectIdentifier((1023,4194303))]
for value in primitives:
    encoded = bytes(value.encode().encode().pduData)
    output = moon("tags",encoded)
    assert output == encoded, (type(value).__name__,encoded.hex(),output.hex())
    decoded = value.__class__.decode(TagList.decode(PDU(output)))
    assert bytes(decoded.encode().encode().pduData) == encoded

queries = [
    ("whois",WhoIsRequest()),
    ("whois",WhoIsRequest(deviceInstanceRangeLowLimit=1,deviceInstanceRangeHighLimit=100)),
    ("iam",IAmRequest(iAmDeviceIdentifier=("device",42),maxAPDULengthAccepted=1476,segmentationSupported="noSegmentation",vendorID=999)),
    ("rp",ReadPropertyRequest(objectIdentifier=("analogInput",1),propertyIdentifier="presentValue")),
    ("rp",ReadPropertyRequest(objectIdentifier=("device",42),propertyIdentifier="objectList",propertyArrayIndex=0)),
    ("rp-ack",ReadPropertyACK(objectIdentifier=("analogInput",1),propertyIdentifier="presentValue",propertyValue=Real(20.0))),
    ("wp",WritePropertyRequest(objectIdentifier=("analogValue",1),propertyIdentifier="presentValue",propertyValue=Real(24.0),priority=8)),
    ("wp",WritePropertyRequest(objectIdentifier=("analogValue",1),propertyIdentifier="presentValue",propertyValue=Null(()),priority=8)),
    ("rpm",ReadPropertyMultipleRequest(listOfReadAccessSpecs=[ReadAccessSpecification(objectIdentifier=("analogInput",1),listOfPropertyReferences=[PropertyReference("presentValue"),PropertyReference("units")])])),
    ("cov-sub",SubscribeCOVRequest(subscriberProcessIdentifier=5,monitoredObjectIdentifier=("analogInput",1),issueConfirmedNotifications=False,lifetime=0)),
    ("cov-sub",SubscribeCOVRequest(subscriberProcessIdentifier=5,monitoredObjectIdentifier=("analogInput",1))),
    ("cov",UnconfirmedCOVNotificationRequest(subscriberProcessIdentifier=5,initiatingDeviceIdentifier=("device",42),monitoredObjectIdentifier=("analogInput",1),timeRemaining=15,listOfValues=[PropertyValue(propertyIdentifier="presentValue",value=Real(23.0)),PropertyValue(propertyIdentifier="statusFlags",value=BitString([0,0,0,0]))])),
    ("rp-ack",ReadPropertyACK(objectIdentifier=("device",42),propertyIdentifier=512,propertyValue=ArrayOf(Unsigned)([]))),
]
for mode,q in queries:
    header(q)
    original = wire(q)
    assert moon(mode,bytes(q.encode().pduData)) == bytes(q.encode().pduData), mode
    output = moon("apdu",original)
    decoded = APCISequence.decode(APDU.decode(PDU(output)))
    assert wire(decoded) == original, mode
    n = NPDU(original)
    n.pduExpectingReply = isinstance(q,ConfirmedRequestPDU)
    nw = bytes(n.encode().pduData)
    assert moon("npdu",nw) == nw
    for cls in [OriginalUnicastNPDU,OriginalBroadcastNPDU]:
        bw = bytes(cls(nw).encode().pduData)
        assert moon("bvlc",bw) == bw

print(f"BACpypes3 0.0.110: {len(primitives)} typed primitives and {len(queries)} service/envelope vectors passed both directions")

process = subprocess.Popen([str(exe),"peer"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
counter = 0
def exchange(q, broadcast=False):
    global counter
    counter += 1
    header(q,counter)
    n = NPDU(wire(q)); n.pduExpectingReply = isinstance(q,ConfirmedRequestPDU)
    cls = OriginalBroadcastNPDU if broadcast else OriginalUnicastNPDU
    packet = bytes(cls(bytes(n.encode().pduData)).encode().pduData)
    process.stdin.write(packet.hex()+"\n"); process.stdin.flush()
    line = process.stdout.readline().strip()
    assert line and line != "-", f"No response for {type(q).__name__}: {line!r}"
    link = LPDU.decode(PDU(bytes.fromhex(line)))
    assert link.bvlciFunction == 10
    network = NPDU.decode(PDU(link.pduData))
    raw = APDU.decode(PDU(network.pduData))
    assert raw.apduType == 1 or raw.apduInvokeID == counter
    if raw.apduType in (0,1,3,5):
        return APCISequence.decode(raw)
    return raw

try:
    iam = exchange(WhoIsRequest(),broadcast=True)
    assert iam.iAmDeviceIdentifier == ObjectIdentifier(("device",42))
    write = WritePropertyRequest(objectIdentifier=("analogValue",1),propertyIdentifier="presentValue",propertyValue=Real(24.0),priority=8)
    assert exchange(write).apduType == 2
    def read():
        result = exchange(ReadPropertyRequest(objectIdentifier=("analogValue",1),propertyIdentifier="presentValue"))
        return float(result.propertyValue.cast_out(Real))
    assert read() == 24.0
    assert exchange(WritePropertyRequest(objectIdentifier=("analogValue",1),propertyIdentifier="presentValue",propertyValue=Real(25.0),priority=16)).apduType == 2
    assert read() == 24.0  # lower priority remains masked
    assert exchange(WritePropertyRequest(objectIdentifier=("analogValue",1),propertyIdentifier="presentValue",propertyValue=Null(()),priority=8)).apduType == 2
    assert read() == 25.0
    rpm = exchange(queries[8][1])
    assert len(rpm.listOfReadAccessResults[0].listOfResults) == 2
    missing = exchange(ReadPropertyRequest(objectIdentifier=("analogInput",1),propertyIdentifier=9999))
    assert int(missing.errorClass) == 2 and int(missing.errorCode) == 32
    assert exchange(queries[9][1]).apduType == 2
    assert exchange(queries[10][1]).apduType == 2
    process.stdin.close()
    assert process.wait(timeout=10) == 0, process.stderr.read()
finally:
    if process.poll() is None:
        process.kill(); process.wait(timeout=10)
print(f"Persistent MoonBit device host: {counter} BACpypes3 exchanges passed discovery, priority write/read/relinquish, RPM, errors and COV subscribe/cancel (stdio; no external device)")

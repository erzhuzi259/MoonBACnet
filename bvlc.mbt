pub(all) enum Bvlc {
  ResultCode(Int)
  RegisterForeign(Int)
  OriginalUnicast(Bytes)
  OriginalBroadcast(Bytes)
  Forwarded(Bytes, Bytes)
  DistributeBroadcast(Bytes)
} derive(Debug)

pub fn encode_bvlc(frame : Bvlc, limits? : Limits = Limits::default()) -> Bytes raise BacnetError {
  limits.validate()
  let body = Writer::new(limits.max_bytes)
  let function = match frame {
    ResultCode(code) => { require_range(code, 0, 65535, "BVLC result"); body.uint(code.reinterpret_as_uint(), 2); 0 }
    RegisterForeign(ttl) => { require_range(ttl, 0, 65535, "foreign TTL"); body.uint(ttl.reinterpret_as_uint(), 2); 5 }
    OriginalUnicast(bytes) => { body.put(bytes); 10 }
    OriginalBroadcast(bytes) => { body.put(bytes); 11 }
    Forwarded(address, bytes) => {
      if address.length() != 6 { raise Invalid("IPv4 and port address length", 0) }
      body.put(address); body.put(bytes); 4
    }
    DistributeBroadcast(bytes) => { body.put(bytes); 9 }
  }
  let bytes = body.finish()
  if bytes.length() > 65531 { raise Limit("BVLC 16-bit length") }
  let w = Writer::new(limits.max_bytes)
  w.u8(0x81); w.u8(function); w.uint((bytes.length()+4).reinterpret_as_uint(), 2); w.put(bytes)
  w.finish()
}

pub fn decode_bvlc(data : Bytes, limits? : Limits = Limits::default()) -> Bvlc raise BacnetError {
  let r = Reader::new(data, limits)
  if r.u8() != 0x81 { raise Unsupported("not BACnet IPv4 BVLC") }
  let function = r.u8()
  if r.uint(2) != data.length().reinterpret_as_uint() { raise Invalid("BVLC datagram length", 2) }
  let result : Bvlc = match function {
    0 => ResultCode(r.uint(2).reinterpret_as_int())
    5 => RegisterForeign(r.uint(2).reinterpret_as_int())
    10 => OriginalUnicast(r.take(r.remaining()))
    11 => OriginalBroadcast(r.take(r.remaining()))
    4 => Forwarded(r.take(6), r.take(r.remaining()))
    9 => DistributeBroadcast(r.take(r.remaining()))
    _ => raise Unsupported("BVLC management function")
  }
  r.done()
  result
}

pub extend Bvlc with @debug.Debug::{to_repr}

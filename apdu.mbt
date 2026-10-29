pub(all) struct Request {
  invoke : Int
  service : Int
  max_apdu : Int
  max_segments : Int
  segmented_response_accepted : Bool
  body : Bytes
} derive(Debug)

pub(all) enum Apdu {
  Confirmed(Request)
  Unconfirmed(Int, Bytes)
  SimpleAck(Int, Int)
  ComplexAck(Int, Int, Bytes)
  ErrorPdu(Int, Int, Bytes)
  Reject(Int, Int)
  Abort(Int, Bool, Int)
} derive(Debug)

pub fn max_apdu_size(code : Int) -> Int raise BacnetError {
  match code {
    0 => 50
    1 => 128
    2 => 206
    3 => 480
    4 => 1024
    5 => 1476
    _ => raise Invalid("max APDU code", 0)
  }
}

pub fn Request::new(invoke : Int, service : Int, body : Bytes, max_apdu? : Int = 5) -> Request raise BacnetError {
  require_range(invoke, 0, 255, "invoke ID")
  require_range(service, 0, 255, "service choice")
  ignore(max_apdu_size(max_apdu))
  { invoke, service, max_apdu, max_segments: 0, segmented_response_accepted: false, body }
}

pub fn encode_apdu(apdu : Apdu, limits? : Limits = Limits::default()) -> Bytes raise BacnetError {
  limits.validate()
  let w = Writer::new(limits.max_bytes)
  match apdu {
    Confirmed(r) => {
      require_range(r.invoke, 0, 255, "invoke ID")
      require_range(r.service, 0, 255, "service choice")
      require_range(r.max_segments, 0, 7, "max segments code")
      ignore(max_apdu_size(r.max_apdu))
      w.u8(if r.segmented_response_accepted { 2 } else { 0 })
      w.u8((r.max_segments << 4) | r.max_apdu)
      w.u8(r.invoke); w.u8(r.service); w.put(r.body)
    }
    Unconfirmed(service, body) => { w.u8(0x10); w.u8(service); w.put(body) }
    SimpleAck(invoke, service) => { w.u8(0x20); w.u8(invoke); w.u8(service) }
    ComplexAck(invoke, service, body) => { w.u8(0x30); w.u8(invoke); w.u8(service); w.put(body) }
    ErrorPdu(invoke, service, body) => { w.u8(0x50); w.u8(invoke); w.u8(service); w.put(body) }
    Reject(invoke, reason) => { w.u8(0x60); w.u8(invoke); w.u8(reason) }
    Abort(invoke, server, reason) => { w.u8(if server { 0x71 } else { 0x70 }); w.u8(invoke); w.u8(reason) }
  }
  w.finish()
}

pub fn decode_apdu(data : Bytes, limits? : Limits = Limits::default()) -> Apdu raise BacnetError {
  let r = Reader::new(data, limits)
  let first = r.u8()
  let kind = first >> 4
  let flags = first & 15
  let result : Apdu = match kind {
    0 => {
      if (flags & 13) != 0 { raise Unsupported("segmented or reserved confirmed request") }
      let sizes = r.u8()
      let max_apdu = sizes & 15
      ignore(max_apdu_size(max_apdu))
      if (sizes >> 4) > 7 { raise Invalid("max segments code", 1) }
      let invoke = r.u8()
      let service = r.u8()
      Confirmed({ invoke, service, max_apdu, max_segments: sizes >> 4,
        segmented_response_accepted: flags == 2, body: r.take(r.remaining()) })
    }
    1 => { if flags != 0 { raise Invalid("unconfirmed flags", 0) }; Unconfirmed(r.u8(), r.take(r.remaining())) }
    2 => { if flags != 0 { raise Invalid("simple ack flags", 0) }; SimpleAck(r.u8(), r.u8()) }
    3 => { if flags != 0 { raise Unsupported("segmented or reserved complex ack") }; ComplexAck(r.u8(), r.u8(), r.take(r.remaining())) }
    5 => { if flags != 0 { raise Invalid("error flags", 0) }; ErrorPdu(r.u8(), r.u8(), r.take(r.remaining())) }
    6 => { if flags != 0 { raise Invalid("reject flags", 0) }; Reject(r.u8(), r.u8()) }
    7 => { if flags > 1 { raise Invalid("abort flags", 0) }; Abort(r.u8(), flags == 1, r.u8()) }
    _ => raise Unsupported("APDU type or segmentation")
  }
  r.done()
  result
}

pub extend Request with @debug.Debug::{to_repr}

pub extend Apdu with @debug.Debug::{to_repr}

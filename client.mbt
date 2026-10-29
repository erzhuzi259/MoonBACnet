///|
priv struct PendingRequest {
  peer : String
  request : Request
  wire : Bytes
  mut deadline : UInt64
  mut retries : Int32
}

///|
pub(all) struct Transmission {
  peer : String
  invoke : Int32
  bytes : Bytes
} derive(Debug)

///|
pub(all) enum Completion {
  Completed(Apdu)
  ServiceError(UInt32, UInt32)
  Rejected(Int32)
  Aborted(Bool, Int32)
} derive(Debug)

///|
pub(all) enum ClientEvent {
  Retry(Transmission)
  TimedOut(String, Int32)
} derive(Debug)

///|
pub struct Client {
  priv limits : Limits
  priv timeout : UInt64
  priv retry_limit : Int32
  priv pending : Array[PendingRequest]
  priv mut retained : Int32
  priv mut next_invoke : Int
  priv mut now : UInt64
}

///|
pub fn Client::new(
  timeout~ : UInt64 = 3UL,
  retries~ : Int32 = 2,
  limits~ : Limits = Limits::default(),
) -> Client raise BacnetError {
  limits.validate()
  if timeout == 0UL || retries < 0 || retries > 16 {
    raise Invalid("client timing policy", 0)
  }
  { limits, timeout, retry_limit: retries, pending: [], retained: 0, now: 0UL, next_invoke: 0, }
}

///|
fn Client::clock(self : Client, now : UInt64) -> Unit raise BacnetError {
  if now < self.now {
    raise State("host clock moved backwards")
  }
  self.now = now
}

///|
pub fn Client::start(
  self : Client,
  peer : String,
  service : Int32,
  body : Bytes,
  now : UInt64,
  max_apdu~ : Int32 = 5,
) -> Transmission raise BacnetError {
  self.clock(now)
  if peer.is_empty() {
    raise Invalid("empty client peer", 0)
  }
  let peer_bytes = text_bytes(peer, 256).length()
  if self.pending.length() >= self.limits.max_pending {
    raise Limit("pending requests")
  }
  if self.timeout > 18446744073709551615UL - now {
    raise State("request deadline overflow")
  }
  let mut invoke = self.next_invoke
  let mut examined = 0
  while examined < 256 {
    let mut used = false
    for entry in self.pending {
      if entry.peer == peer && entry.request.invoke == invoke {
        used = true
        break
      }
    }
    if !used {
      break
    }
    invoke = (invoke+1)%256
    examined += 1
  }
  if examined == 256 {
    raise Limit("all peer invoke IDs occupied")
  }
  let request = Request::new(invoke, service, body, max_apdu~)
  let bytes = encode_datagram(Confirmed(request), limits=self.limits)
  if bytes.length() - 6 > 1476 {
    raise Limit("client unsegmented APDU")
  }
  let cost = bytes.length() + peer_bytes
  if cost > self.limits.max_bytes - self.retained {
    raise Limit("pending request bytes")
  }
  self.pending.push({
    peer,
    request,
    wire: bytes,
    deadline: now + self.timeout,
    retries: 0,
  })
  self.retained += cost
  self.next_invoke = (invoke+1)%256
  { peer, invoke, bytes, }
}

///|
fn Client::remove(self : Client, index : Int32) -> Unit raise BacnetError {
  let entry = self.pending[index]
  self.retained -= entry.wire.length() + text_bytes(entry.peer, 256).length()
  self.pending.remove(index) |> ignore
}

///|
pub fn Client::pending_count(self : Client) -> Int32 {
  self.pending.length()
}

///|
pub fn Client::cancel(
  self : Client,
  peer : String,
  invoke : Int32,
) -> Bool raise BacnetError {
  for i = 0; i < self.pending.length(); i = i + 1 {
    if self.pending[i].peer == peer && self.pending[i].request.invoke == invoke {
      self.remove(i)
      return true
    }
  }
  false
}

///|
pub fn Client::receive(
  self : Client,
  peer : String,
  response : Apdu,
  now : UInt64,
) -> Completion? raise BacnetError {
  self.clock(now)
  let (invoke, service) = match response {
    SimpleAck(id, choice)
    | ComplexAck(id, choice, _)
    | ErrorPdu(id, choice, _) => (id, Some(choice))
    Reject(id, _) | Abort(id, _, _) => (id, None)
    _ => return None
  }
  let mut index = -1
  for i = 0; i < self.pending.length(); i = i + 1 {
    if self.pending[i].peer == peer && self.pending[i].request.invoke == invoke {
      index = i
      break
    }
  }
  if index < 0 {
    return None
  }
  let request = self.pending[index].request
  if service is Some(choice) && choice != request.service {
    raise State("response service mismatch")
  }
  if encode_apdu(response, limits=self.limits).length() >
    max_apdu_size(request.max_apdu) {
    raise Limit("response exceeds advertised APDU")
  }
  let result = match response {
    ComplexAck(_, 12, bytes) => {
      let ack = decode_property_ack(bytes, limits=self.limits)
      if ack.reference != decode_read_property(request.body, limits=self.limits) {
        raise State("response property reference mismatch")
      }
      Completed(response)
    }
    ComplexAck(_, 14, bytes) => {
      ignore(decode_multiple_ack(bytes, limits=self.limits))
      Completed(response)
    }
    SimpleAck(_, 5) | SimpleAck(_, 15) => Completed(response)
    ErrorPdu(_, _, bytes) => {
      let (class, code) = decode_error(bytes)
      ServiceError(class, code)
    }
    Reject(_, reason) => Rejected(reason)
    Abort(_, server, reason) => Aborted(server, reason)
    _ => raise Unsupported("response form for service")
  }
  self.remove(index)
  Some(result)
}

///|
pub fn Client::poll(
  self : Client,
  now : UInt64,
) -> Array[ClientEvent] raise BacnetError {
  self.clock(now)
  let events : Array[ClientEvent] = []
  let remove : Array[Int32] = []
  for i = 0; i < self.pending.length(); i = i + 1 {
    let entry = self.pending[i]
    if now < entry.deadline {
      continue
    }
    if entry.retries >= self.retry_limit ||
      self.timeout > 18446744073709551615UL - now {
      events.push(TimedOut(entry.peer, entry.request.invoke))
      remove.push(i)
    } else {
      events.push(
        Retry({
          peer: entry.peer,
          invoke: entry.request.invoke,
          bytes: entry.wire,
        }),
      )
      entry.retries += 1
      entry.deadline = now + self.timeout
    }
  }
  for i = remove.length() - 1; i >= 0; i = i - 1 {
    self.remove(remove[i])
  }
  events
}

///|
pub extend Transmission with @debug.Debug::{to_repr}

///|
pub extend Completion with @debug.Debug::{to_repr}

///|
pub extend ClientEvent with @debug.Debug::{to_repr}


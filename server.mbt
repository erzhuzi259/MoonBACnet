///|
pub struct Server {
  priv device : Device
  priv cov : CovManager
  priv cache : Array[CachedReply]
  priv mut now : UInt64
  priv mut cache_bytes : Int32
  priv mut cov_client : Client?
  priv cov_pending : Array[CovPending]
  priv received_notifications : Array[CovEnvelope]
}

///|
pub fn Server::new(device : Device) -> Server {
  {
    device,
    cov: CovManager::new(device),
    cache: [],
    now: 0UL,
    cache_bytes: 0,
    cov_client: None,
    cov_pending: [],
    received_notifications: [],
  }
}

///|
pub fn Server::device(self : Server) -> Device {
  self.device
}

///|
pub fn Server::notifications(
  self : Server,
  now : UInt64,
) -> Array[CovEnvelope] raise BacnetError {
  self.clock(now)
  self.cov.poll(now)
}

///|
fn Device::read_access(
  self : Device,
  access : Array[ReadAccess],
) -> Array[ReadAccessResult] raise BacnetError {
  let output : Array[ReadAccessResult] = []
  let mut total = 0
  let mut retained = 0
  for entry in access {
    let results : Array[ReadResult] = []
    let resolved = if entry.object.kind == 8 &&
      entry.object.instance == 4194303 &&
      entry.properties.any(p => p.0 == 75U) {
      self.id
    } else {
      entry.object
    }
    for (property, index) in entry.properties {
      let properties = if (
          property == 8U || property == 105U || property == 80U
        ) &&
        index == None {
        self.select_properties(resolved, property) catch {
          Property(_, _) => [property]
          error => raise error
        }
      } else {
        [property]
      }
      let properties = if properties.is_empty() {
        [property]
      } else {
        properties
      }
      for p in properties {
        if total >= self.limits.max_nodes {
          raise Limit("expanded read access results")
        }
        total += 1
        let reference : PropertyRef = { object: resolved, property: p, index, }
        let result = PropertyData(reference, self.read(reference)) catch {
          Property(class, code) => PropertyFailure(reference, class, code)
          error => raise error
        }
        let cost = match result {
          PropertyData(_, value) =>
            encode_tags(value, limits=self.limits).length() + 20
          PropertyFailure(_, _, _) => 24
        }
        if cost > self.limits.max_bytes - retained {
          raise Limit("read access result bytes")
        }
        retained += cost
        results.push(result)
      }
    }
    output.push({ object: resolved, results, })
  }
  output
}

///|
fn Server::confirmed(
  self : Server,
  request : Request,
  peer : String,
  now : UInt64,
) -> Apdu raise BacnetError {
  match request.service {
    1 => {
      self.receive_notification(
        peer,
        decode_cov(request.body, limits=self.device.limits),
      )
      SimpleAck(request.invoke, 1)
    }
    12 => {
      let reference = decode_read_property(
        request.body,
        limits=self.device.limits,
      )
      let reference = self.device.read_reference(reference)
      let value = self.device.read(reference)
      ComplexAck(
        request.invoke,
        12,
        encode_property_ack({ reference, value, }, limits=self.device.limits),
      )
    }
    14 => {
      let access = decode_read_multiple(request.body, limits=self.device.limits)
      let results = self.device.read_access(access)
      ComplexAck(
        request.invoke,
        14,
        encode_multiple_ack(results, limits=self.device.limits),
      )
    }
    15 => {
      let write = decode_write_property(request.body, limits=self.device.limits)
      self.device.write(write)
      SimpleAck(request.invoke, 15)
    }
    5 => {
      self.cov.subscribe(
        peer,
        decode_subscribe_cov(request.body, limits=self.device.limits),
        now,
      )
      SimpleAck(request.invoke, 5)
    }
    _ => Reject(request.invoke, 9)
  }
}

///|
pub fn Server::handle(
  self : Server,
  apdu : Apdu,
  peer : String,
  now : UInt64,
) -> Apdu? raise BacnetError {
  self.clock(now)
  let request_wire = encode_apdu(apdu, limits=self.device.limits)
  if request_wire.length() > 1476 {
    raise Limit("device receive APDU maximum")
  }
  match apdu {
    SimpleAck(_, _) | ErrorPdu(_, _, _) | Reject(_, _) | Abort(_, _, _) => {
      if self.cov_client is Some(client) {
        ignore(client.receive(peer, apdu, now))
        self.cleanup_cov(now)
      }
      None
    }
    Unconfirmed(2, body) => {
      self.receive_notification(
        peer,
        decode_cov(body, limits=self.device.limits),
      )
      None
    }
    Confirmed(request) => {
      if peer.is_empty() {
        raise Invalid("empty request peer", 0)
      }
      let peer_bytes = text_bytes(peer, 256).length()
      for i = 0; i < self.cache.length(); i = i + 1 {
        let cached = self.cache[i]
        if cached.peer == peer && cached.invoke == request.invoke {
          if cached.request == request_wire {
            return Some(decode_apdu(cached.response, limits=self.device.limits))
          }
          self.cache_bytes -= cached.request.length() +
            cached.response.length() +
            text_bytes(cached.peer, 256).length()
          self.cache.remove(i) |> ignore
          break
        }
      }
      let response = self.confirmed(request, peer, now) catch {
        Property(class, code) =>
          ErrorPdu(request.invoke, request.service, encode_error(class, code))
        Invalid(_, _) => Reject(request.invoke, 4)
        Unsupported(_) => Reject(request.invoke, 9)
        Limit(_) => Abort(request.invoke, true, 1)
        error => raise error
      }
      let response_wire = encode_apdu(response, limits=self.device.limits) catch {
        Limit(_) =>
          encode_apdu(Abort(request.invoke, true, 1), limits=self.device.limits)
        error => raise error
      }
      let response_wire = if response_wire.length() >
        max_apdu_size(request.max_apdu) {
        encode_apdu(Abort(request.invoke, true, 11), limits=self.device.limits)
      } else {
        response_wire
      }
      let cost = request_wire.length() + response_wire.length() + peer_bytes
      let budget = self.device.limits.max_bytes * 2 + 256
      while !self.cache.is_empty() &&
            (
              self.cache.length() >= self.device.limits.max_pending ||
              cost > budget - self.cache_bytes
            ) {
        let old = self.cache[0]
        self.cache_bytes -= old.request.length() +
          old.response.length() +
          text_bytes(old.peer, 256).length()
        self.cache.remove(0) |> ignore
      }
      self.cache.push({
        peer,
        invoke: request.invoke,
        request: request_wire,
        response: response_wire,
        at: now,
      })
      self.cache_bytes += cost
      Some(decode_apdu(response_wire, limits=self.device.limits))
    }
    Unconfirmed(7, body) =>
      match
        self.device.discover_object(
          decode_who_has(body, limits=self.device.limits),
        ) {
        Some(value) =>
          Some(Unconfirmed(1, encode_i_have(value, limits=self.device.limits)))
        None => None
      }
    Unconfirmed(8, body) => {
      let range = decode_who_is(body, limits=self.device.limits)
      let instance = self.device.id.instance
      if (range.low is Some(low) && instance < low) ||
        (range.high is Some(high) && instance > high) {
        return None
      }
      Some(
        Unconfirmed(
          0,
          encode_i_am(self.device.announcement(), limits=self.device.limits),
        ),
      )
    }
    _ => None
  }
}

///|
pub fn Server::datagram(
  self : Server,
  bytes : Bytes,
  peer : String,
  now : UInt64,
) -> Bytes? raise BacnetError {
  let (npdu_bytes, broadcast) = match
    decode_bvlc(bytes, limits=self.device.limits) {
    OriginalUnicast(payload) => (payload, false)
    OriginalBroadcast(payload) => (payload, true)
    _ =>
      raise Unsupported(
        "device host accepts only original local-network datagrams",
      )
  }
  let npdu = decode_npdu(npdu_bytes, limits=self.device.limits)
  if npdu.destination is Some(_) || npdu.source is Some(_) {
    raise Unsupported("device host does not route")
  }
  if npdu.payload.length() > 1476 {
    raise Limit("device receive APDU maximum")
  }
  if !broadcast &&
    npdu.expecting_reply &&
    npdu.payload.length() >= 6 &&
    (npdu.payload[0].to_int() & 0xf9) == 8 {
    ignore(max_apdu_size(npdu.payload[1].to_int() & 15))
    if npdu.payload[1].to_int() >> 4 > 7 ||
      npdu.payload[4].to_int() == 0 ||
      npdu.payload[4].to_int() > 127 {
      raise Invalid("segmented request header", 0)
    }
    self.clock(now)
    return Some(
      encode_datagram(
        Abort(npdu.payload[2].to_int(), true, 4),
        limits=self.device.limits,
      ),
    )
  }
  let apdu = decode_apdu(npdu.payload, limits=self.device.limits)
  if broadcast && apdu is Confirmed(_) {
    return None
  }
  if npdu.expecting_reply != (apdu is Confirmed(_)) {
    raise Invalid("NPDU expecting-reply mismatch", 1)
  }
  match self.handle(apdu, peer, now) {
    None => None
    Some(response) =>
      Some(
        encode_bvlc(
          OriginalUnicast(
            encode_npdu(
              Npdu::for_local(encode_apdu(response, limits=self.device.limits)),
              limits=self.device.limits,
            ),
          ),
          limits=self.device.limits,
        ),
      )
  }
}

///|
pub fn encode_datagram(
  apdu : Apdu,
  broadcast~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let expecting_reply = apdu is Confirmed(_)
  let npdu = encode_npdu(
    Npdu::for_local(encode_apdu(apdu, limits~), expecting_reply~),
    limits~,
  )
  encode_bvlc(
    if broadcast {
      OriginalBroadcast(npdu)
    } else {
      OriginalUnicast(npdu)
    },
    limits~,
  )
}

///|
pub fn decode_datagram(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> Apdu raise BacnetError {
  let payload = match decode_bvlc(bytes, limits~) {
    OriginalUnicast(p)
    | OriginalBroadcast(p)
    | Forwarded(_, p)
    | DistributeBroadcast(p) => p
    _ => raise Invalid("BVLC has no application data", 0)
  }
  decode_apdu(decode_npdu(payload, limits~).payload, limits~)
}

///|
priv struct CachedReply {
  peer : String
  invoke : Int32
  request : Bytes
  response : Bytes
  at : UInt64
}

///|
fn Server::clock(self : Server, now : UInt64) -> Unit raise BacnetError {
  if now < self.now {
    raise State("server host clock moved backwards")
  }
  self.now = now
  for i = self.cache.length() - 1; i >= 0; i = i - 1 {
    let entry = self.cache[i]
    if now - entry.at >= 30UL {
      self.cache_bytes -= entry.request.length() +
        entry.response.length() +
        text_bytes(entry.peer, 256).length()
      self.cache.remove(i) |> ignore
    }
  }
}

///|
pub struct Server {
  priv device : Device
  priv cov : CovManager
}

///|
pub fn Server::new(device : Device) -> Server {
  { device, cov: CovManager::new(device), }
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
    for (property, index) in entry.properties {
      let properties = if property == 8U && index == None {
        self.all_property_ids(entry.object) catch {
          Property(_, _) => [property]
          error => raise error
        }
      } else {
        [property]
      }
      for p in properties {
        if total >= self.limits.max_nodes {
          raise Limit("expanded read access results")
        }
        total += 1
        let reference : PropertyRef = {
          object: entry.object,
          property: p,
          index,
        }
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
    output.push({ object: entry.object, results, })
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
    12 => {
      let reference = decode_read_property(
        request.body,
        limits=self.device.limits,
      )
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
  if encode_apdu(apdu, limits=self.device.limits).length() > 1476 {
    raise Limit("device receive APDU maximum")
  }
  match apdu {
    Confirmed(request) => {
      let response = self.confirmed(request, peer, now) catch {
        Property(class, code) =>
          ErrorPdu(request.invoke, request.service, encode_error(class, code))
        Invalid(_, _) => Reject(request.invoke, 4)
        Unsupported(_) => Reject(request.invoke, 9)
        Limit(_) => Abort(request.invoke, true, 1)
        error => raise error
      }
      if encode_apdu(response, limits=self.device.limits).length() >
        max_apdu_size(request.max_apdu) {
        Some(Abort(request.invoke, true, 11))
      } else {
        Some(response)
      }
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
  let npdu_bytes = match decode_bvlc(bytes, limits=self.device.limits) {
    OriginalUnicast(payload) | OriginalBroadcast(payload) => payload
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
  let apdu = decode_apdu(npdu.payload, limits=self.device.limits)
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

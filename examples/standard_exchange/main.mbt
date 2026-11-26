///|
fn request(
  server : @bac.Server,
  invoke : Int32,
  service : Int32,
  body : Bytes,
  now : UInt64,
) -> @bac.Apdu raise {
  let wire = @bac.encode_datagram(
    Confirmed(@bac.Request::new(invoke, service, body)),
  )
  @bac.decode_datagram(server.datagram(wire, "collector", now).unwrap())
}

///|
fn main raise {
  let device = @bac.Device::new_standard(42, "standard-device", 999U, {
    instance: 1,
    name: "ipv4",
    address: b"\x7f\x00\x00\x01",
    subnet_mask: b"\xff\x00\x00\x00",
    gateway: b"\x00\x00\x00\x00",
    udp_port: 47808U,
  })
  let point = @bac.ObjectId::new(2, 1)
  device.add_point(
    point,
    "room-setpoint",
    Analog,
    Real(19.0F),
    commandable=true,
  )
  let server = @bac.Server::new(device)
  let who_has = @bac.encode_who_has({
    range: { low: None, high: None, },
    object: Name("room-setpoint"),
  })
  match server.handle(Unconfirmed(7, who_has), "collector", 0UL) {
    Some(Unconfirmed(1, body)) => {
      assert_eq(@bac.decode_i_have(body).object, point)
      println("Who-Has(room-setpoint) -> I-Have(device,42; analog-value,1)")
    }
    _ => raise Failure("I-Have expected")
  }
  match
    request(
      server,
      1,
      12,
      @bac.encode_read_property({
        object: @bac.ObjectId::new(8, 4194303),
        property: 75U,
        index: None,
      }),
      0UL,
    ) {
    ComplexAck(_, 12, body) => {
      assert_eq(
        @bac.decode_property_ack(body).reference.object,
        device.identifier(),
      )
      println("ReadProperty(device,4194303,Object_Identifier) -> device,42")
    }
    _ => raise Failure("ReadPropertyACK expected")
  }
  for selector in [8U, 105U, 80U] {
    assert_true(
      request(
        server,
        selector.reinterpret_as_int(),
        14,
        @bac.encode_read_multiple([
          { object: point, properties: [(selector, None)], },
        ]),
        0UL,
      )
      is ComplexAck(_, 14, _),
    )
  }
  let mixed = @bac.encode_read_multiple([
    {
      object: point,
      properties: [(85U, None), (87U, Some(0U)), (9999U, None)],
    },
  ])
  match request(server, 2, 14, mixed, 0UL) {
    ComplexAck(_, 14, body) => {
      let results = @bac.correlate_read_multiple(mixed, body)
      assert_true(results[0] is PropertyData(_, [Application(Real(19.0F))]))
      assert_true(results[1] is PropertyData(_, [Application(Unsigned(16U))]))
      assert_true(results[2] is PropertyFailure(_, 2U, 32U))
      println("RPM -> REAL(19), priority count 16, PROPERTY/UNKNOWN_PROPERTY")
    }
    _ => raise Failure("RPM acknowledgement expected")
  }
  let sub = @bac.encode_subscribe_cov({
    process: 7U,
    object: point,
    confirmed: Some(true),
    lifetime: Some(5U),
  })
  assert_true(request(server, 3, 5, sub, 0UL) is SimpleAck(3, 5))
  let outgoing = server.confirmed_notifications(0UL)[0]
  assert_eq(server.confirmed_notifications(3UL)[0].bytes, outgoing.bytes)
  let observer = @bac.Server::new(@bac.Device::new(43, "observer", 999U))
  let ack = observer.datagram(outgoing.bytes, "device", 3UL).unwrap()
  ignore(observer.datagram(outgoing.bytes, "device", 3UL))
  assert_eq(observer.take_notifications().length(), 1)
  ignore(server.datagram(ack, "collector", 3UL))
  assert_eq(server.notification_deadline(), None)
  println("Confirmed COV -> exact retry -> SimpleACK -> one observation")
  let cancel = @bac.encode_subscribe_cov({
    process: 7U,
    object: point,
    confirmed: None,
    lifetime: None,
  })
  assert_true(request(server, 4, 5, cancel, 4UL) is SimpleAck(4, 5))
  assert_eq(server.confirmed_notifications(7UL).length(), 0)
}

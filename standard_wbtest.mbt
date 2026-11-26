///|
fn standard_test_device() -> Device raise BacnetError {
  Device::new_standard(42, "standard", 999U, {
    instance: 1,
    name: "ipv4",
    address: b"\x7f\x00\x00\x01",
    subnet_mask: b"\xff\x00\x00\x00",
    gateway: b"\x00\x00\x00\x00",
    udp_port: 47808U,
  })
}

///|
test "standard constructor exposes device identity and configured IPv4 port" {
  let d = standard_test_device()
  assert_eq(
    scalar_wire(d, d.id, property=139U),
    encode_tags([Application(Unsigned(22U))]),
  )
  assert_eq(d.read(reference(d.id, property=76U)).length(), 2)
  let port = ObjectId::new(56, 1)
  assert_eq(
    scalar_wire(d, port, property=400U),
    encode_tags([Application(Octets(b"\x7f\x00\x00\x01"))]),
  )
  assert_eq(
    scalar_wire(d, port, property=427U),
    encode_tags([Application(Enumerated(5U))]),
  )
  for property in d.required_property_ids(d.id) {
    ignore(d.read(reference(d.id, property~)))
  }
  for property in d.required_property_ids(port) {
    ignore(d.read(reference(port, property~)))
  }
  expect_error(() => {
    ignore(
      Device::new_standard(1, "d", 1U, {
        instance: 1,
        name: "bad",
        address: b"\x00",
        subnet_mask: b"\x00\x00\x00\x00",
        gateway: b"\x00\x00\x00\x00",
        udp_port: 0U,
      }),
    )
  })
}

///|
test "Who-Has matches a name or identifier and filters device ranges" {
  let d = sample_device()
  let s = Server::new(d)
  let q : WhoHas = {
    range: { low: None, high: None, },
    object: Name("setpoint"),
  }
  let bytes = encode_who_has(q)
  assert_eq(encode_who_has(decode_who_has(bytes)), bytes)
  match s.handle(Unconfirmed(7, bytes), "a", 0UL) {
    Some(Unconfirmed(1, body)) => {
      let found = decode_i_have(body)
      assert_eq(found.object, ObjectId::new(2, 1))
      assert_eq(found.name, "setpoint")
    }
    _ => fail("missing I-Have")
  }
  let id_query = { ..q, object: Identifier(ObjectId::new(2, 1)), }
  assert_true(
    s.handle(Unconfirmed(7, encode_who_has(id_query)), "a", 0UL)
    is Some(Unconfirmed(1, _)),
  )
  assert_true(
    s.handle(
      Unconfirmed(7, encode_who_has({ ..q, object: Name("missing"), })),
      "a",
      0UL,
    )
    is None,
  )
  assert_true(
    s.handle(
      Unconfirmed(
        7,
        encode_who_has({ ..q, range: { low: Some(43), high: Some(50), }, }),
      ),
      "a",
      0UL,
    )
    is None,
  )
  expect_error(() => {
    ignore(
      decode_who_has(
        encode_tags([context_uint(0, 1U), context_object(2, d.id)]),
      ),
    )
  })
}

///|
test "wildcard Device Object_Identifier works through client and RPM" {
  let d = standard_test_device()
  let s = Server::new(d)
  let c = Client::new()
  let wildcard = ObjectId::new(8, 4194303)
  let body = encode_read_property(reference(wildcard, property=75U))
  let tx = c.start("device", 12, body, 0UL)
  let ack = decode_datagram(s.datagram(tx.bytes, "client", 0UL).unwrap())
  assert_true(
    c.receive("device", ack, 0UL) is Some(Completed(ComplexAck(_, 12, _))),
  )
  let rpm = encode_read_multiple([
    { object: wildcard, properties: [(75U, None)], },
  ])
  match request_reply(s, 20, 14, rpm) {
    ComplexAck(_, 14, body) => {
      let result = decode_multiple_ack(body)
      assert_eq(result[0].object, d.id)
      assert_eq(correlate_read_multiple(rpm, body).length(), 1)
    }
    _ => fail("wildcard RPM failed")
  }
}

///|
test "REQUIRED OPTIONAL and ALL distinguish standard properties and custom fields" {
  let d = standard_test_device()
  d.define_property(d.id, 512U, [Application(Text("custom"))])
  let s = Server::new(d)
  for selector in [8U, 105U, 80U] {
    let request = encode_read_multiple([
      { object: d.id, properties: [(selector, None)], },
    ])
    match request_reply(s, selector.reinterpret_as_int(), 14, request) {
      ComplexAck(_, 14, body) => {
        let results = decode_multiple_ack(body)[0].results
        assert_true(
          results.any(r => r is PropertyData({ property: 512U, .. }, _)) ==
          (selector != 105U),
        )
        assert_true(
          results.any(r => r is PropertyData({ property: 139U, .. }, _)) ==
          (selector != 80U),
        )
      }
      _ => fail("selector request failed")
    }
  }
}

///|
test "network rename checks uniqueness and input OOS controls Present_Value writes" {
  let d = sample_device()
  let input = ObjectId::new(0, 1)
  expect_error(() => {
    d.write({
      reference: reference(input),
      value: [Application(Real(11.0F))],
      priority: None,
    })
  })
  d.write({
    reference: reference(input, property=81U),
    value: [Application(Boolean(true))],
    priority: None,
  })
  assert_eq(
    scalar_wire(d, input, property=111U),
    encode_tags([Application(Bits(4, b"\x10"))]),
  )
  d.write({
    reference: reference(input),
    value: [Application(Real(11.0F))],
    priority: None,
  })
  assert_eq(scalar_wire(d, input), encode_tags([Application(Real(11.0F))]))
  expect_error(() => {
    d.write({
      reference: reference(input, property=77U),
      value: [Application(Text("setpoint"))],
      priority: None,
    })
  })
  assert_eq(
    scalar_wire(d, input, property=77U),
    encode_tags([Application(Text("temperature"))]),
  )
  assert_eq(
    scalar_wire(d, ObjectId::new(2, 1), property=431U),
    encode_tags([Application(Null)]),
  )
}

///|
test "segmented request produces a protocol Abort and next legal request works" {
  let s = Server::new(sample_device())
  let packet = encode_bvlc(
    OriginalUnicast(
      encode_npdu(
        Npdu::for_local(b"\x0c\x05\x07\x00\x01\x0c", expecting_reply=true),
      ),
    ),
  )
  assert_true(
    decode_datagram(s.datagram(packet, "client", 0UL).unwrap())
    is Abort(7, true, 4),
  )
  assert_true(
    request_reply(
      s,
      8,
      12,
      encode_read_property(reference(ObjectId::new(0, 1))),
    )
    is ComplexAck(8, 12, _),
  )
}

///|
test "confirmed COV retries exact frames and drains once across duplicate receipt" {
  let d = sample_device()
  let s = Server::new(d)
  let receiver = Server::new(Device::new(43, "observer", 999U))
  let sub : SubscribeCov = {
    process: 7U,
    object: ObjectId::new(0, 1),
    confirmed: Some(true),
    lifetime: Some(20U),
  }
  assert_true(
    request_reply(s, 9, 5, encode_subscribe_cov(sub)) is SimpleAck(9, 5),
  )
  assert_eq(s.notifications(0UL).length(), 0)
  let first = s.confirmed_notifications(0UL)
  assert_eq(first.length(), 1)
  assert_eq(s.notification_deadline(), Some(3UL))
  assert_eq(s.confirmed_notifications(2UL).length(), 0)
  let retry = s.confirmed_notifications(3UL)
  assert_eq(retry[0].bytes, first[0].bytes)
  let ack = receiver.datagram(first[0].bytes, "device", 3UL).unwrap()
  ignore(receiver.datagram(first[0].bytes, "device", 3UL))
  assert_eq(receiver.take_notifications().length(), 1)
  assert_eq(receiver.take_notifications().length(), 0)
  ignore(s.datagram(ack, "peer-a", 3UL))
  assert_eq(s.notification_deadline(), None)
  d.update(sub.object, 85U, Real(21.0F))
  assert_eq(s.confirmed_notifications(4UL).length(), 1)
  ignore(
    request_reply(
      s,
      10,
      5,
      encode_subscribe_cov({ ..sub, confirmed: None, lifetime: None, }),
      now=4UL,
    ),
  )
  assert_eq(s.confirmed_notifications(7UL).length(), 0)
  assert_eq(s.notification_deadline(), None)
}

///|
test "confirmed COV admission failure leaves initial snapshots available for retry" {
  let d = Device::new(42, "bounded", 999U, limits={
    ..Limits::default(),
    max_pending: 1,
  })
  let id = ObjectId::new(0, 1)
  d.add_point(id, "temp", Analog, Real(20.0F))
  let s = Server::new(d)
  for peer in ["a", "b"] {
    ignore(
      s.handle(
        Confirmed(
          Request::new(
            1,
            5,
            encode_subscribe_cov({
              process: 1U,
              object: id,
              confirmed: Some(true),
              lifetime: Some(20U),
            }),
          ),
        ),
        peer,
        0UL,
      ),
    )
  }
  expect_error(() => ignore(s.confirmed_notifications(0UL)))
  assert_eq(s.notification_deadline(), None)
  ignore(
    s.handle(
      Confirmed(
        Request::new(
          2,
          5,
          encode_subscribe_cov({
            process: 1U,
            object: id,
            confirmed: None,
            lifetime: None,
          }),
        ),
      ),
      "b",
      0UL,
    ),
  )
  assert_eq(s.confirmed_notifications(1UL).length(), 1)
}

///|
test "confirmed COV timeout is bounded and subscription expiry cancels retransmission" {
  let s = Server::new(sample_device())
  let body = encode_subscribe_cov({
    process: 1U,
    object: ObjectId::new(0, 1),
    confirmed: Some(true),
    lifetime: Some(30U),
  })
  ignore(request_reply(s, 1, 5, body))
  assert_eq(s.confirmed_notifications(0UL).length(), 1)
  assert_eq(s.confirmed_notifications(3UL).length(), 1)
  assert_eq(s.confirmed_notifications(6UL).length(), 1)
  assert_eq(s.confirmed_notifications(9UL).length(), 0)
  assert_eq(s.notification_deadline(), None)
  assert_eq(s.confirmed_notifications(30UL).length(), 0)
}

///|
test "all nine point kinds supply their required properties and command priority tracks release" {
  let d = standard_test_device()
  for kind in [0, 1, 2, 3, 4, 5, 13, 14, 19] {
    let id = ObjectId::new(kind, 1)
    let domain = if kind <= 2 {
      Analog
    } else if kind <= 5 {
      Binary
    } else {
      MultiState(3U)
    }
    let value = match domain {
      Analog => Real(19.0F)
      Binary => Enumerated(0U)
      MultiState(_) => Unsigned(1U)
    }
    d.add_point(
      id,
      "point-" + kind.to_string(),
      domain,
      value,
      commandable=kind == 1 || kind == 4 || kind == 14,
    )
    for property in d.required_property_ids(id) {
      ignore(d.read(reference(id, property~)))
    }
  }
  let id = ObjectId::new(1, 1)
  d.write({
    reference: reference(id),
    value: [Application(Real(23.0F))],
    priority: Some(8),
  })
  assert_eq(
    scalar_wire(d, id, property=431U),
    encode_tags([Application(Unsigned(8U))]),
  )
  d.write({
    reference: reference(id),
    value: [Application(Null)],
    priority: Some(8),
  })
  assert_eq(scalar_wire(d, id, property=431U), encode_tags([Application(Null)]))
  d.write({
    reference: reference(ObjectId::new(2, 1)),
    value: [Application(Real(21.0F))],
    priority: None,
  })
  assert_eq(
    scalar_wire(d, ObjectId::new(2, 1)),
    encode_tags([Application(Real(21.0F))]),
  )
}

///|
test "mismatched wildcard acknowledgement leaves the request pending" {
  let c = Client::new()
  let request = encode_read_property(
    reference(ObjectId::new(8, 4194303), property=75U),
  )
  let tx = c.start("peer", 12, request, 0UL)
  let bad = ComplexAck(
    tx.invoke,
    12,
    encode_property_ack({
      reference: reference(ObjectId::new(2, 1), property=75U),
      value: [Application(Object(ObjectId::new(2, 1)))],
    }),
  )
  expect_error(() => ignore(c.receive("peer", bad, 0UL)))
  assert_eq(c.pending_count(), 1)
}

///|
test "wrong notification acknowledgement service does not settle the COV transaction" {
  let s = Server::new(sample_device())
  ignore(
    request_reply(
      s,
      1,
      5,
      encode_subscribe_cov({
        process: 1U,
        object: ObjectId::new(0, 1),
        confirmed: Some(true),
        lifetime: Some(10U),
      }),
    ),
  )
  let tx = s.confirmed_notifications(0UL)[0]
  expect_error(() => ignore(s.handle(SimpleAck(tx.invoke, 15), "peer-a", 1UL)))
  assert_eq(s.notification_deadline(), Some(3UL))
  assert_eq(s.confirmed_notifications(3UL)[0].invoke, tx.invoke)
}

///|
test "malformed Who-Has ranges and choices are rejected" {
  for
    tags in [
      [
        context_uint(0, 50U),
        context_uint(1, 40U),
        context_object(2, ObjectId::new(2, 1)),
      ],
      [
        context_uint(0, 0U),
        context_uint(1, 4194304U),
        context_object(2, ObjectId::new(2, 1)),
      ],
      [context_object(2, ObjectId::new(2, 1)), Context(3, b"\x00extra")],
      [Context(2, b"\x00")],
    ] {
    expect_error(() => ignore(decode_who_has(encode_tags(tags))))
  }
}

///|
test "database revision changes with schema and names while default writes restore correctly" {
  let d = standard_test_device()
  let before = d.database_revision
  let id = ObjectId::new(2, 1)
  d.add_point(id, "control", Analog, Real(19.0F), commandable=true)
  assert_true(d.database_revision > before)
  let added = d.database_revision
  d.write({
    reference: reference(id, property=77U),
    value: [Application(Text("renamed"))],
    priority: None,
  })
  assert_true(d.database_revision > added)
  assert_eq(
    scalar_wire(d, d.id, property=155U),
    encode_tags([Application(Unsigned(d.database_revision))]),
  )
  d.write({
    reference: reference(id, property=104U),
    value: [Application(Real(17.0F))],
    priority: None,
  })
  assert_eq(scalar_wire(d, id), encode_tags([Application(Real(17.0F))]))
  let stable = d.database_revision
  expect_error(() => {
    d.write({
      reference: reference(id, property=104U),
      value: [Application(Unsigned(1U))],
      priority: None,
    })
  })
  assert_eq(d.database_revision, stable)
  assert_eq(scalar_wire(d, id), encode_tags([Application(Real(17.0F))]))
}

///|
test "received confirmed notification queue is bounded and duplicates do not consume it" {
  let observer = Server::new(
    Device::new(43, "observer", 999U, limits={
      ..Limits::default(),
      max_pending: 1,
    }),
  )
  let body = encode_cov({
    process: 7U,
    device: ObjectId::new(8, 42),
    object: ObjectId::new(0, 1),
    remaining: 10U,
    values: [
      {
        property: 85U,
        index: None,
        value: [Application(Real(20.0F))],
        priority: None,
      },
    ],
  })
  assert_true(
    observer.handle(Confirmed(Request::new(1, 1, body)), "peer", 0UL)
    is Some(SimpleAck(1, 1)),
  )
  assert_true(
    observer.handle(Confirmed(Request::new(1, 1, body)), "peer", 0UL)
    is Some(SimpleAck(1, 1)),
  )
  assert_true(
    observer.handle(Confirmed(Request::new(2, 1, body)), "peer", 0UL)
    is Some(Abort(2, true, 1)),
  )
  assert_eq(observer.take_notifications().length(), 1)
  assert_true(
    observer.handle(Confirmed(Request::new(3, 1, body)), "peer", 0UL)
    is Some(SimpleAck(3, 1)),
  )
  assert_eq(observer.take_notifications().length(), 1)
}

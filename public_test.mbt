///|
test "public API permits consumer discovery and exact property construction" {
  let device = @moonbacnet.Device::new(42, "consumer-device", 999U)
  let id = @moonbacnet.ObjectId::new(2, 1)
  device.add_point(id, "setpoint", Analog, Real(19.0F), commandable=true)
  let server = @moonbacnet.Server::new(device)
  let client = @moonbacnet.Client::new()
  let reference : @moonbacnet.PropertyRef = {
    object: id,
    property: 85U,
    index: None,
  }
  let tx = client.start(
    "device",
    12,
    @moonbacnet.encode_read_property(reference),
    0UL,
  )
  let response = server.datagram(tx.bytes, "client", 0UL).unwrap()
  match client.receive("device", @moonbacnet.decode_datagram(response), 0UL) {
    Some(Completed(ComplexAck(_, 12, body))) => {
      let ack = @moonbacnet.decode_property_ack(body)
      assert_eq(ack.reference, reference)
      assert_eq(
        @moonbacnet.encode_tags(ack.value),
        @moonbacnet.encode_tags([Application(Real(19.0F))]),
      )
    }
    _ => fail("external consumer request failed")
  }
}

///|
test "public errors expose invalid wire unsupported profile limits and property failure" {
  let invalid = try {
    ignore(@moonbacnet.decode_tags(b"\x21"))
    false
  } catch {
    @moonbacnet.BacnetError::Invalid(_, _) => true
    _ => false
  }
  assert_true(invalid)
  let unsupported = try {
    ignore(@moonbacnet.decode_npdu(b"\x01\x80\x00"))
    false
  } catch {
    @moonbacnet.BacnetError::Unsupported(_) => true
    _ => false
  }
  assert_true(unsupported)
  let d = @moonbacnet.Device::new(1, "d", 1U)
  let missing = try {
    ignore(d.read({ object: d.identifier(), property: 9999U, index: None, }))
    false
  } catch {
    @moonbacnet.BacnetError::Property(2U, 32U) => true
    _ => false
  }
  assert_true(missing)
}

///|
test "public value layer retains precision and compound data independent of device profile" {
  let values : Array[@moonbacnet.Tag] = [
    Application(Unsigned(4294967295U)),
    Application(DoubleValue(0x7ff8000000000012UL.reinterpret_as_double())),
    Constructed(254, [Application(Octets(b"\x00\xff")), Context(20, b"abc")]),
  ]
  let wire = @moonbacnet.encode_tags(values)
  assert_eq(@moonbacnet.encode_tags(@moonbacnet.decode_tags(wire)), wire)
  assert_eq(@moonbacnet.hex_decode(@moonbacnet.hex_encode(wire)), wire)
}

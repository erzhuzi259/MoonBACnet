///|
priv struct RandomState {
  mut state : UInt32
}

///|
fn RandomState::next(self : RandomState) -> UInt32 {
  self.state = self.state * 1664525U + 1013904223U
  self.state
}

///|
fn RandomState::small(self : RandomState, bound : Int32) -> Int32 {
  (self.next() % bound.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn generated_tag(rng : RandomState, depth : Int32) -> Tag raise BacnetError {
  let choice = rng.small(if depth < 4 { 12 } else { 10 })
  match choice {
    0 => Application(Null)
    1 => Application(Boolean(rng.small(2) == 1))
    2 => Application(Unsigned(rng.next()))
    3 => Application(Signed(rng.next().reinterpret_as_int()))
    4 => Application(Real(Float::reinterpret_from_uint(rng.next())))
    5 => Application(Enumerated(rng.next()))
    6 => Application(Text("text-月-\{rng.small(1000)}"))
    7 => Application(Object(ObjectId::from_number(rng.next())))
    8 =>
      Context(
        rng.small(255),
        Bytes::from_array(Array::make(rng.small(32), rng.small(256).to_byte())),
      )
    9 =>
      Application(
        Bits(
          0,
          Bytes::from_array(
            Array::make(rng.small(16), rng.small(256).to_byte()),
          ),
        ),
      )
    _ => {
      let children : Array[Tag] = []
      for i = 0; i < rng.small(4); i = i + 1 {
        children.push(generated_tag(rng, depth + 1))
      }
      Constructed(rng.small(255), children)
    }
  }
}

///|
test "generated structured trees normalize idempotently" {
  let rng : RandomState = { state: 0x1badb002U, }
  for i = 0; i < 1000; i = i + 1 {
    let tag = generated_tag(rng, 0)
    let bytes = encode_tags([tag])
    assert_eq(encode_tags(decode_tags(bytes)), bytes)
  }
}

///|
test "random bounded wire cannot bypass errors or fail canonical idempotence" {
  let rng : RandomState = { state: 0xdeadbeefU, }
  let limits = {
    ..Limits::default(),
    max_bytes: 256,
    max_nodes: 64,
    max_depth: 8,
  }
  for i = 0; i < 4000; i = i + 1 {
    let data : Array[Byte] = []
    let length = rng.small(80)
    for j = 0; j < length; j = j + 1 {
      data.push(rng.small(256).to_byte())
    }
    let wire = Bytes::from_array(data)
    let decoded = Some(decode_tags(wire, limits~)) catch { _ => None }
    if decoded is Some(tags) {
      let encoded = encode_tags(tags, limits~)
      assert_eq(encode_tags(decode_tags(encoded, limits~), limits~), encoded)
    }
    ignore(decode_bvlc(wire, limits~)) catch {
      _ => ()
    }
    ignore(decode_npdu(wire, limits~)) catch {
      _ => ()
    }
    ignore(decode_apdu(wire, limits~)) catch {
      _ => ()
    }
  }
}

///|
test "every truncated prefix of a wrapped value and datagram is rejected" {
  let bytes = encode_tags([
    Constructed(254, [
      Application(Text("月 🌙")),
      Application(Octets(b"abcdef")),
      Constructed(2, [Application(Unsigned(4294967295U))]),
    ]),
  ])
  for n = 1; n < bytes.length(); n = n + 1 {
    expect_error(() => ignore(decode_tags(bytes[0:n].to_owned())))
  }
  let datagram = encode_datagram(
    Confirmed(
      Request::new(1, 12, encode_read_property(reference(ObjectId::new(0, 1)))),
    ),
  )
  for n = 0; n < datagram.length(); n = n + 1 {
    expect_error(() => ignore(decode_datagram(datagram[0:n].to_owned())))
  }
}

///|
test "large pseudo-range requests are bounded by retained results rather than numeric property IDs" {
  let server = Server::new(sample_device())
  let body = encode_read_multiple([
    {
      object: ObjectId::new(0, 1),
      properties: [(4294967295U, None), (85U, Some(4294967295U))],
    },
  ])
  match request_reply(server, 1, 14, body) {
    ComplexAck(_, 14, bytes) => {
      let results = decode_multiple_ack(bytes)[0].results
      assert_true(results[0] is PropertyFailure(_, 2U, 32U))
      assert_true(results[1] is PropertyFailure(_, 2U, 50U))
    }
    _ => fail("expected per-property errors")
  }
}

///|
fn expect_error(action : () -> Unit raise BacnetError) -> Unit raise {
  let rejected = try {
    action()
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
fn check_tags(tags : Array[Tag]) -> Unit raise {
  let bytes = encode_tags(tags)
  assert_eq(encode_tags(decode_tags(bytes)), bytes)
}

///|
test "known wire scalar encodings are exact and signed widths minimal" {
  assert_eq(
    hex_encode(
      encode_tags([
        Application(Null),
        Application(Boolean(false)),
        Application(Boolean(true)),
      ]),
    ),
    "001011",
  )
  assert_eq(
    hex_encode(
      encode_tags([Application(Unsigned(256U)), Application(Signed(-129))]),
    ),
    "22010032ff7f",
  )
  assert_eq(
    hex_encode(encode_tags([Application(Object(ObjectId::new(1, 2)))])),
    "c400400002",
  )
  for
    value in [
      -2147483648, -8388609, -8388608, -32769, -32768, -129, -128, 0, 127, 128, 32767,
      32768, 2147483647,
    ] {
    let wire = encode_tags([Application(Signed(value))])
    match decode_tags(wire)[:] {
      [Application(Signed(decoded))] => assert_eq(decoded, value)
      _ => fail("signed domain lost")
    }
  }
}

///|
test "exact integer floating bits and every primitive domain round trip" {
  let values : Array[Value] = [
    Unsigned(4294967295U),
    Signed(-2147483648),
    Enumerated(4294967295U),
    Real(Float::reinterpret_from_uint(0x7fc12345U)),
    Real(-0.0F),
    DoubleValue(0x7ff8000000000123UL.reinterpret_as_double()),
    DoubleValue(-0.0),
    Octets(b"\x00\xff"),
    Text("月 🌙\u{feff}\u0000"),
    Bits(5, b"\xa0"),
    Bits(0, b""),
    DateValue({ year: 126, month: 13, day: 32, weekday: 255, }),
    TimeValue({ hour: 255, minute: 59, second: 59, hundredth: 99, }),
    Object(ObjectId::new(1023, 4194303)),
  ]
  for value in values {
    check_tags([Application(value)])
  }
}

///|
test "extended lengths and tag numbers include all boundaries" {
  for length in [0, 1, 4, 5, 253, 254, 255, 256, 65530] {
    let limits = { ..Limits::default(), max_bytes: 70000, }
    let bytes = Bytes::from_array(Array::make(length, 0x42))
    for number in [0, 14, 15, 254] {
      let wire = encode_tags([Context(number, bytes)], limits~)
      let read = decode_tags(wire, limits~)
      assert_eq(encode_tags(read, limits~), wire)
    }
  }
  let large = { ..Limits::default(), max_bytes: 100000, }
  let wire = encode_tags(
    [Application(Octets(Bytes::from_array(Array::make(65536, 0))))],
    limits=large,
  )
  assert_eq(encode_tags(decode_tags(wire, limits=large), limits=large), wire)
}

///|
test "constructed contexts empty and nested preserve matching closing tags" {
  check_tags([
    Constructed(0, []),
    Constructed(20, [
      Context(8, b""),
      Constructed(254, [Application(Boolean(true))]),
    ]),
  ])
  for wire in [b"\x0e", b"\x0f", b"\x0e\x1f", b"\x06", b"\x07", b"\xf8\xff"] {
    expect_error(() => ignore(decode_tags(wire)))
  }
}

///|
test "application malformed widths text bit padding and calendar are rejected" {
  let malformed : Array[Bytes] = [
    b"\x01\x00", b"\x12", b"\x20", b"\x25\x05\x00\x00\x00\x00\x00", b"\x43\x00\x00\x00",
    b"\x54\x00\x00\x00\x00", b"\x70", b"\x72\x00\xff", b"\x72\x01\x41", b"\x81\x08",
    b"\x82\x01\x01", b"\xa4\x7e\x00\x01\x01", b"\xb4\x18\x00\x00\x00", b"\xc3\x00\x00\x00",
  ]
  for wire in malformed {
    expect_error(() => ignore(decode_tags(wire)))
  }
  expect_error(() => ignore(encode_tags([Application(Bits(1, b"\x01"))])))
  expect_error(() => ignore(ObjectId::new(1024, 0)))
  expect_error(() => ignore(ObjectId::new(0, -1)))
}

///|
test "depth node and announced byte budgets stop hostile containers" {
  let limits = { ..Limits::default(), max_nodes: 2, max_depth: 1, }
  expect_error(() => ignore(decode_tags(b"\x00\x00\x00", limits~)))
  expect_error(() => {
    ignore(
      encode_tags(
        [Constructed(0, [Constructed(1, [Application(Null)])])],
        limits~,
      ),
    )
  })
  expect_error(() => ignore(decode_tags(b"\x65\xff\xff\xff\xff\xff")))
  expect_error(() => {
    ignore(
      encode_tags([Context(0, Bytes::from_array(Array::make(64, 0)))], limits={
        ..limits,
        max_bytes: 64,
      }),
    )
  })
  expect_error(() => {
    ignore(decode_tags(b"", limits={ ..limits, max_depth: 129, }))
  })
}

///|
test "nonminimal legal integer encodings normalize without changing domain" {
  assert_eq(encode_tags(decode_tags(b"\x24\x00\x00\x00\x01")), b"\x21\x01")
  assert_eq(encode_tags(decode_tags(b"\x34\xff\xff\xff\xff")), b"\x31\xff")
  assert_eq(hex_decode("00fFaB"), b"\x00\xff\xab")
  expect_error(() => ignore(hex_decode("abc")))
  expect_error(() => ignore(hex_decode("0g")))
}

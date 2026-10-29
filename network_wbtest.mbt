test "BVLC known datagram and fixed management bodies round trip" {
  let wire = encode_bvlc(OriginalBroadcast(b"\x01\x00\x10\x08"))
  assert_eq(hex_encode(wire), "810b000801001008")
  for frame in [ResultCode(0), ResultCode(0x60), RegisterForeign(65535),
    OriginalUnicast(b"abc"), OriginalBroadcast(b"abc"), DistributeBroadcast(b"abc"), Forwarded(b"\x7f\x00\x00\x01\xba\xc0", b"abc")] {
    let bytes = encode_bvlc(frame)
    assert_eq(encode_bvlc(decode_bvlc(bytes)), bytes)
  }
}

test "BVLC length mismatch truncation and unsupported management fail" {
  for data in [b"", b"\x81", b"\x81\x00\x00\x04", b"\x81\x05\x00\x07\x00\x01\x00",
    b"\x81\x0a\x00\x05", b"\x82\x0a\x00\x04", b"\x81\x01\x00\x04", b"\x81\x04\x00\x08\x00\x00\x00\x00"] {
    expect_error(() => { ignore(decode_bvlc(data)) })
  }
  expect_error(() => { ignore(encode_bvlc(Forwarded(b"12345", b""))) })
  expect_error(() => { ignore(encode_bvlc(RegisterForeign(-1))) })
}

test "routed NPDU retains independent source destination priority and hop" {
  let npdu : Npdu = { destination: Some({ network: 300, address: b"\x05\x06" }),
    source: Some({ network: 4, address: b"\x07" }), hop_count: 12, expecting_reply: true, priority: 3,
    payload: b"\x10\x08" }
  let bytes = encode_npdu(npdu)
  assert_eq(hex_encode(bytes), "012f012c020506000401070c1008")
  assert_eq(encode_npdu(decode_npdu(bytes)), bytes)
  let broadcast = { ..npdu, destination: Some({ network: 65535, address: b"" }), source: None }
  assert_eq(encode_npdu(decode_npdu(encode_npdu(broadcast))), encode_npdu(broadcast))
}

test "NPDU rejects invalid routes reserved flags network messages and empty APDU" {
  for bytes in [b"\x01\x00", b"\x02\x00\x10\x08", b"\x01\x40\x10\x08", b"\x01\x80\x00",
    b"\x01\x08\x00\x01\x00\x10\x08", b"\x01\x20\xff\xff\x01\x00\xff\x10\x08"] {
    expect_error(() => { ignore(decode_npdu(bytes)) })
  }
  expect_error(() => { ignore(encode_npdu({ ..Npdu::for_local(b"x"), priority: 4 })) })
  expect_error(() => { ignore(encode_npdu({ ..Npdu::for_local(b"x"), source: Some({ network: 65535, address: b"a" }) })) })
}

test "all unsegmented APDU forms preserve header data and maxima" {
  let apdus : Array[Apdu] = [Confirmed(Request::new(255, 12, b"abc")),
    Confirmed({ ..Request::new(0, 14, b""), max_segments: 7, segmented_response_accepted: true }),
    Unconfirmed(8, b""), SimpleAck(5, 15), ComplexAck(4, 12, b"abc"),
    ErrorPdu(3, 15, encode_error(2U, 40U)), Reject(2, 9), Abort(1, true, 4), Abort(0, false, 0)]
  for apdu in apdus {
    let bytes = encode_apdu(apdu)
    assert_eq(encode_apdu(decode_apdu(bytes)), bytes)
  }
  assert_eq(max_apdu_size(0), 50)
  assert_eq(max_apdu_size(5), 1476)
  expect_error(() => { ignore(max_apdu_size(6)) })
}

test "APDU flags segmentation trailing bytes and identifier validation are strict" {
  for bytes in [b"\x08\x05\x01\x00\x01\x0c", b"\x04\x05\x01\x0c", b"\x01\x05\x01\x0c",
    b"\x00\xf5\x01\x0c", b"\x00\x06\x01\x0c", b"\x21\x01\x0c", b"\x20\x01\x0c\x00",
    b"\x38\x01\x00\x01\x0c", b"\x40\x01\x00\x01", b"\x72\x01\x00", b"\x60\x01"] {
    expect_error(() => { ignore(decode_apdu(bytes)) })
  }
  expect_error(() => { ignore(Request::new(-1, 12, b"")) })
  expect_error(() => { ignore(encode_apdu(SimpleAck(256, 15))) })
}

test "complete datagram envelopes decode application messages" {
  let query = Unconfirmed(8, encode_who_is({ low: None, high: None }))
  let bytes = encode_datagram(query, broadcast=true)
  assert_eq(bytes, b"\x81\x0b\x00\x08\x01\x00\x10\x08")
  assert_eq(encode_apdu(decode_datagram(bytes)), encode_apdu(query))
  expect_error(() => { ignore(decode_datagram(encode_bvlc(ResultCode(0)))) })
}

fn sample_device() -> Device raise BacnetError {
  let d = Device::new(42,"test-device",999U)
  d.add_point(ObjectId::new(0,1),"temperature",Analog,Real(20.0F),units=62U)
  d.add_point(ObjectId::new(2,1),"setpoint",Analog,Real(19.0F),commandable=true,units=62U)
  d.add_point(ObjectId::new(5,1),"alarm",Binary,Enumerated(0U),commandable=true)
  d
}

fn request_reply(server : Server, invoke : Int, service : Int, body : Bytes, now? : UInt64 = 0UL, max_apdu? : Int = 5) -> Apdu raise BacnetError {
  server.handle(Confirmed(Request::new(invoke,service,body,max_apdu~)),"peer-a",now).unwrap()
}

test "server discover read write release and unknown property map to independent forms" {
  let server = Server::new(sample_device())
  let id = ObjectId::new(2,1)
  match server.handle(Unconfirmed(8,b""),"peer-a",0UL) {
    Some(Unconfirmed(0,body)) => assert_eq(decode_i_am(body).device,ObjectId::new(8,42))
    _ => fail("missing IAm")
  }
  assert_true(server.handle(Unconfirmed(8,encode_who_is({low:Some(43),high:Some(100)})),"peer-a",0UL) is None)
  let write = encode_write_property({reference:reference(id),value:[Application(Real(24.0F))],priority:Some(8)})
  assert_true(request_reply(server,1,15,write) is SimpleAck(1,15))
  match request_reply(server,2,12,encode_read_property(reference(id))) {
    ComplexAck(2,12,body) => assert_eq(encode_tags(decode_property_ack(body).value),encode_tags([Application(Real(24.0F))]))
    _ => fail("missing read ACK")
  }
  match request_reply(server,3,12,encode_read_property(reference(id,property=9999U))) {
    ErrorPdu(3,12,body) => assert_eq(decode_error(body),(2U,32U))
    _ => fail("missing property error")
  }
  match request_reply(server,4,12,encode_read_property(reference(ObjectId::new(0,999)))) {
    ErrorPdu(_,_,body) => assert_eq(decode_error(body),(1U,31U))
    _ => fail("missing object error")
  }
}

test "server RPM expands all and carries per-property errors without discarding successes" {
  let server = Server::new(sample_device())
  let id = ObjectId::new(0,1)
  let request = encode_read_multiple([{object:id,properties:[(85U,None),(999U,None)]}])
  match request_reply(server,1,14,request) {
    ComplexAck(_,14,body) => {
      let results = decode_multiple_ack(body)[0].results
      assert_true(results[0] is PropertyData(_,_))
      assert_true(results[1] is PropertyFailure(_,2U,32U))
    }
    _ => fail("missing RPM ACK")
  }
  match request_reply(server,2,14,encode_read_multiple([{object:id,properties:[(8U,None)]}])) {
    ComplexAck(_,14,body) => assert_eq(decode_multiple_ack(body)[0].results.length(),server.device().all_property_ids(id).length())
    _ => fail("missing all-property expansion")
  }
}

test "server request cache deduplicates retries but accepts changed request with reused invoke" {
  let server = Server::new(sample_device())
  let id = ObjectId::new(2,1)
  let write = encode_write_property({reference:reference(id),value:[Application(Real(24.0F))],priority:Some(8)})
  ignore(request_reply(server,7,15,write))
  server.device().write({reference:reference(id),value:[Application(Null)],priority:Some(8)})
  assert_true(request_reply(server,7,15,write,now=1UL) is SimpleAck(7,15))
  assert_eq(server.device().active_priority(id),None)
  let changed = encode_write_property({reference:reference(id),value:[Application(Real(22.0F))],priority:Some(8)})
  ignore(request_reply(server,7,15,changed,now=2UL))
  assert_eq(server.device().active_priority(id),Some(8))
  ignore(request_reply(server,7,15,write,now=32UL))
  assert_eq(scalar_wire(server.device(),id),encode_tags([Application(Real(24.0F))]))
  expect_error(() => { ignore(request_reply(server,9,12,b"",now=31UL)) })
}

test "server malformed or unsupported services get reject and oversize replies get abort" {
  let server = Server::new(sample_device())
  assert_true(request_reply(server,1,12,b"\x09") is Reject(1,4))
  assert_true(request_reply(server,2,255,b"") is Reject(2,9))
  let id = ObjectId::new(2,1)
  let body = encode_write_property({reference:reference(id),value:[Application(Real(30.0F))],priority:Some(6)})
  match request_reply(server,3,15,body) {
    ErrorPdu(_,_,bytes) => assert_eq(decode_error(bytes),(2U,37U))
    _ => fail("reserved priority must fail")
  }
  let read_all = encode_read_multiple([{object:id,properties:[(8U,None)]}])
  assert_true(request_reply(server,4,14,read_all,max_apdu=0) is Abort(4,true,11))
  assert_eq(server.device().active_priority(id),None)
}

test "datagram host refuses routed forwarded broadcast confirmed and reply flag mismatches" {
  let server = Server::new(sample_device())
  let read = Confirmed(Request::new(1,12,encode_read_property(reference(ObjectId::new(0,1)))))
  assert_true(server.datagram(encode_datagram(read,broadcast=true),"peer-a",0UL) is None)
  let response = server.datagram(encode_datagram(read),"peer-a",0UL).unwrap()
  assert_true(decode_datagram(response) is ComplexAck(1,12,_))
  expect_error(() => { ignore(server.datagram(encode_bvlc(Forwarded(b"123456",b"\x01\x00\x10\x08")),"x",0UL)) })
  let wrong_flag = encode_bvlc(OriginalUnicast(encode_npdu(Npdu::for_local(encode_apdu(read)))))
  expect_error(() => { ignore(server.datagram(wrong_flag,"x",0UL)) })
  let routed = encode_npdu({ ..Npdu::for_local(b"\x10\x08"),destination:Some({network:2,address:b""}) })
  expect_error(() => { ignore(server.datagram(encode_bvlc(OriginalUnicast(routed)),"x",0UL)) })
}

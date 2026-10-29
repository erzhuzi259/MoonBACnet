test "client round trips server properties and rotates invoke identifiers after completion" {
  let client = Client::new()
  let server = Server::new(sample_device())
  let body = encode_read_property(reference(ObjectId::new(0,1)))
  let tx = client.start("device",12,body,0UL)
  let response = server.datagram(tx.bytes,"client",0UL).unwrap()
  assert_true(client.receive("wrong-peer",decode_datagram(response),0UL) is None)
  assert_eq(client.pending_count(),1)
  assert_true(client.receive("device",decode_datagram(response),0UL) is Some(Completed(ComplexAck(_,12,_))))
  assert_eq(client.pending_count(),0)
  let second = client.start("device",12,body,1UL)
  assert_true(second.invoke != tx.invoke)
}

test "client mismatched service reference and malformed ACK retain pending request" {
  let client = Client::new()
  let id = ObjectId::new(0,1)
  let tx = client.start("device",12,encode_read_property(reference(id)),0UL)
  expect_error(() => { ignore(client.receive("device",SimpleAck(tx.invoke,15),0UL)) })
  expect_error(() => { ignore(client.receive("device",ComplexAck(tx.invoke,12,b""),0UL)) })
  let bad = encode_property_ack({reference:reference(ObjectId::new(0,2)),value:[Application(Real(0.0F))]})
  expect_error(() => { ignore(client.receive("device",ComplexAck(tx.invoke,12,bad),0UL)) })
  assert_eq(client.pending_count(),1)
  assert_true(client.receive("device",ErrorPdu(tx.invoke,12,encode_error(1U,31U)),0UL) is Some(ServiceError(1U,31U)))
  assert_eq(client.pending_count(),0)
}

test "client retries reproduce bytes timeout once and cancellation frees retained state" {
  let client = Client::new(timeout=2UL,retries=1)
  let tx = client.start("peer",12,encode_read_property(reference(ObjectId::new(0,1))),0UL)
  assert_eq(client.poll(1UL).length(),0)
  match client.poll(2UL)[:] {
    [Retry(retry)] => assert_eq(retry.bytes,tx.bytes)
    _ => fail("expected one retransmission")
  }
  assert_eq(client.poll(3UL).length(),0)
  assert_true(client.poll(4UL) is [TimedOut("peer",_)])
  assert_eq(client.poll(5UL).length(),0)
  let later = client.start("peer",12,b"",5UL)
  assert_true(!client.cancel("other",later.invoke))
  assert_true(client.cancel("peer",later.invoke))
  assert_true(!client.cancel("peer",later.invoke))
  expect_error(() => { ignore(client.poll(4UL)) })
}

test "client limits reserved capacity stale responses and deadline overflow" {
  let client = Client::new(limits={ ..Limits::default(),max_pending:1 })
  let first = client.start("a",12,b"",0UL)
  expect_error(() => { ignore(client.start("b",12,b"",0UL)) })
  assert_eq(client.pending_count(),1)
  assert_true(client.receive("a",Reject(first.invoke,9),0UL) is Some(Rejected(9)))
  assert_true(client.receive("a",Reject(first.invoke,9),0UL) is None)
  let last = client.start("b",12,b"",18446744073709551612UL)
  assert_true(client.poll(18446744073709551615UL) is [TimedOut("b",_)])
  assert_true(!client.cancel("b",last.invoke))
  expect_error(() => { ignore(client.start("a",12,b"",18446744073709551615UL)) })
}

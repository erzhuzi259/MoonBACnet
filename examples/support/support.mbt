///|
pub fn transact(
  server : @bac.Server,
  client : @bac.Client,
  service : Int32,
  body : Bytes,
  now : UInt64,
) -> @bac.Completion raise {
  let tx = client.start("device", service, body, now)
  let reply = server.datagram(tx.bytes, "client", now).unwrap()
  client.receive("device", @bac.decode_datagram(reply), now).unwrap()
}

///|
pub fn read(
  server : @bac.Server,
  client : @bac.Client,
  reference : @bac.PropertyRef,
  now : UInt64,
) -> Array[@bac.Tag] raise {
  match
    transact(server, client, 12, @bac.encode_read_property(reference), now) {
    Completed(ComplexAck(_, 12, body)) => @bac.decode_property_ack(body).value
    _ => raise Failure("property read failed")
  }
}

///|
pub fn write(
  server : @bac.Server,
  client : @bac.Client,
  object : @bac.ObjectId,
  value : @bac.Value,
  priority : Int32,
  now : UInt64,
) -> Unit raise {
  let body = @bac.encode_write_property({
    reference: { object, property: 85U, index: None, },
    value: [Application(value)],
    priority: Some(priority),
  })
  match transact(server, client, 15, body, now) {
    Completed(SimpleAck(_, 15)) => ()
    _ => raise Failure("property write failed")
  }
}

///|
pub fn assert_real(value : Array[@bac.Tag], expected : Float) -> Unit raise {
  match value[:] {
    [Application(Real(actual))] if actual == expected => ()
    _ => raise Failure("unexpected REAL property value")
  }
}

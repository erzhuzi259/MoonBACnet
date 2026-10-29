///|
fn main raise {
  let d = @bac.Device::new(7001, "equipment-monitor", 999U)
  let temperature = @bac.ObjectId::new(0, 1)
  let fault = @bac.ObjectId::new(3, 1)
  d.add_point(
    temperature,
    "equipment-temperature",
    Analog,
    Real(20.0F),
    units=62U,
  )
  d.update(temperature, 22U, Real(1.0F))
  d.add_point(fault, "equipment-fault", Binary, Enumerated(0U))
  let server = @bac.Server::new(d)
  let client = @bac.Client::new()
  for id in [temperature, fault] {
    let sub : @bac.SubscribeCov = {
      process: 1U,
      object: id,
      confirmed: Some(false),
      lifetime: Some(5U),
    }
    assert_true(
      @support.transact(server, client, 5, @bac.encode_subscribe_cov(sub), 0UL)
      is Completed(SimpleAck(_, 5)),
    )
  }
  assert_eq(server.notifications(0UL).length(), 2)
  d.update(temperature, 85U, Real(20.5F))
  assert_eq(server.notifications(1UL).length(), 0)
  d.update(temperature, 85U, Real(21.0F))
  d.update(fault, 85U, Enumerated(1U))
  let notifications = server.notifications(2UL)
  assert_eq(notifications.length(), 2)
  for envelope in notifications {
    assert_eq(envelope.notification.remaining, 3U)
    let wire = @bac.encode_datagram(
      Unconfirmed(2, @bac.encode_cov(envelope.notification)),
    )
    match @bac.decode_datagram(wire) {
      Unconfirmed(2, body) =>
        assert_eq(@bac.decode_cov(body).values.length(), 2)
      _ => raise Failure("COV wire decode failed")
    }
  }
  d.update(fault, 85U, Enumerated(0U))
  assert_eq(server.notifications(5UL).length(), 0)
  println(
    "Monitoring: initial snapshots, cumulative analog threshold, binary fault COV, typed notification wire and subscription expiry passed",
  )
}

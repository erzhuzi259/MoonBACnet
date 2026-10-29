///|
fn main raise {
  let device = @bac.Device::new(4201, "office-floor-control", 999U)
  let setpoint = @bac.ObjectId::new(2, 1)
  let temperature = @bac.ObjectId::new(0, 1)
  device.add_point(
    setpoint,
    "room-setpoint",
    Analog,
    Real(19.0F),
    commandable=true,
    units=62U,
  )
  device.add_point(
    temperature,
    "room-temperature",
    Analog,
    Real(20.2F),
    units=62U,
  )
  let server = @bac.Server::new(device)
  let client = @bac.Client::new()
  let present : @bac.PropertyRef = {
    object: setpoint,
    property: 85U,
    index: None,
  }
  @support.write(server, client, setpoint, Real(21.0F), 16, 0UL)
  @support.write(server, client, setpoint, Real(23.0F), 8, 1UL)
  @support.assert_real(@support.read(server, client, present, 2UL), 23.0F)
  @support.write(server, client, setpoint, Real(26.0F), 1, 3UL)
  @support.assert_real(@support.read(server, client, present, 4UL), 26.0F)
  @support.write(server, client, setpoint, Null, 1, 5UL)
  @support.assert_real(@support.read(server, client, present, 6UL), 23.0F)
  @support.write(server, client, setpoint, Null, 8, 7UL)
  @support.assert_real(@support.read(server, client, present, 8UL), 21.0F)
  @support.write(server, client, setpoint, Null, 16, 9UL)
  @support.assert_real(@support.read(server, client, present, 10UL), 19.0F)
  assert_eq(device.active_priority(setpoint), None)
  let slots = @support.read(
    server,
    client,
    { object: setpoint, property: 87U, index: Some(0U), },
    11UL,
  )
  assert_eq(
    @bac.encode_tags(slots),
    @bac.encode_tags([Application(Unsigned(16U))]),
  )
  device.update(temperature, 85U, Real(21.3F))
  @support.assert_real(
    @support.read(
      server,
      client,
      { object: temperature, property: 85U, index: None, },
      12UL,
    ),
    21.3F,
  )
  assert_eq(client.pending_count(), 0)
  println(
    "HVAC: schedule 16, operator 8, override 1; relinquish restores lower slots then default; sensor read passed",
  )
}

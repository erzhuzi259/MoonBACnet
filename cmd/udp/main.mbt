///|
/// Bounded loopback BACnet/IP device adapter for local gateway integration.
/// No broadcast, authentication, BBMD, routing or device certification claimed.
async fn main {
  let args = @env.args()
  if args.length() != 3 {
    raise Failure("usage: moonbacnet-udp PORT MAX_DATAGRAMS")
  }
  let port = @string.parse_int(args[1])
  let maximum = @string.parse_int(args[2])
  if port < 0 || port > 65535 || maximum <= 0 || maximum > 10000 {
    raise Failure("invalid port or datagram budget")
  }
  let device = @bac.Device::new(42, "loopback-controller", 999U)
  device.add_point(
    @bac.ObjectId::new(2, 1),
    "setpoint",
    Analog,
    Real(19.0F),
    commandable=true,
  )
  let server = @bac.Server::new(device)
  let socket = @socket.UdpServer(@socket.Addr::new(0x7f000001U, port))
  defer socket.close()
  @stdio.stdout.write(
    @utf8.encode("READY " + socket.addr.port().to_string() + "\n"),
  )
  let peers : Map[String, @socket.Addr] = Map([])
  let buffer = FixedArray::make(65536, b'\x00')
  let mut processed = 0
  let mut clock = 0UL
  // A finite host session avoids retaining sockets indefinitely in examples/tests.
  @async.with_timeout(15000, async fn() {
    while processed < maximum {
      let packet = @async.with_timeout_opt(100, async fn() {
        socket.recvfrom(buffer)
      })
      let seconds = @async.now() / 1000L
      if seconds >= 0L && seconds.reinterpret_as_uint64() > clock {
        clock = seconds.reinterpret_as_uint64()
      }
      if packet is Some((size, peer)) {
        processed += 1
        let key = peer.to_string()
        if peers.contains(key) || peers.length() < 128 {
          let bytes = Bytes::from_array(Array::makei(size, i => buffer[i]))
          let reply = server.datagram(bytes, key, clock) catch { _ => None }
          peers[key] = peer
          if reply is Some(bytes) {
            socket.sendto(bytes, peer)
          }
        }
      }
      for envelope in server.notifications(clock) {
        if peers.get(envelope.peer) is Some(peer) {
          let bytes = @bac.encode_datagram(
            Unconfirmed(2, @bac.encode_cov(envelope.notification)),
          )
          socket.sendto(bytes, peer)
        }
      }
    }
  })
}

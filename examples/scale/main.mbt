fn main raise {
  let d = @bac.Device::new(8001,"bounded-workload",999U)
  for i = 0; i < 64; i = i+1 {
    d.add_point(@bac.ObjectId::new(2,i),"point-\{i}",Analog,Real(0.0F),commandable=true)
  }
  let server = @bac.Server::new(d)
  let client = @bac.Client::new()
  for i = 0; i < 32; i = i+1 {
    let sub : @bac.SubscribeCov = {process:i.reinterpret_as_uint(),object:@bac.ObjectId::new(2,i),confirmed:Some(false),lifetime:Some(0U)}
    ignore(@support.transact(server,client,5,@bac.encode_subscribe_cov(sub),0UL))
  }
  assert_eq(server.notifications(0UL).length(),32)
  let mut changes = 0
  let mut traffic = 0
  for i = 0; i < 4096; i = i+1 {
    let now = (i+1).to_uint64()
    let id = @bac.ObjectId::new(2,i%64)
    let value = Float::from_int(i+1)
    let body = @bac.encode_write_property({reference:{object:id,property:85U,index:None},value:[Application(Real(value))],priority:Some(8)})
    let tx = client.start("device",15,body,now)
    let reply = server.datagram(tx.bytes,"client",now).unwrap()
    traffic += tx.bytes.length()+reply.length()
    assert_true(client.receive("device",@bac.decode_datagram(reply),now) is Some(Completed(SimpleAck(_,15))))
    @support.assert_real(@support.read(server,client,{object:id,property:85U,index:None},now),value)
    changes += server.notifications(now).length()
    assert_eq(client.pending_count(),0)
  }
  assert_eq(changes,2048)
  println("Scale: 64 points, 32 COV subscriptions, 4096 writes and reads, \{changes} changes; \{traffic} write/reply bytes; no pending transactions")
}

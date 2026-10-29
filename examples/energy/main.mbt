fn main raise {
  let d = @bac.Device::new(5001,"meter-gateway",999U)
  for i = 1; i <= 8; i = i+1 {
    d.add_point(@bac.ObjectId::new(0,i),"meter-\{i}",Analog,Real(Float::from_int(i)*100.0F),units=19U)
  }
  let server = @bac.Server::new(d)
  let client = @bac.Client::new()
  let discovery = server.datagram(@bac.encode_datagram(Unconfirmed(8,@bac.encode_who_is({low:Some(5000),high:Some(5100)})),broadcast=true),"client",0UL).unwrap()
  match @bac.decode_datagram(discovery) {
    Unconfirmed(0,body) => assert_eq(@bac.decode_i_am(body).device,d.identifier())
    _ => raise Failure("device discovery failed")
  }
  let objects = @support.read(server,client,{object:d.identifier(),property:76U,index:None},1UL)
  assert_eq(objects.length(),9)
  let access : Array[@bac.ReadAccess] = []
  for tag in objects {
    if tag is Application(Object(id)) && id.kind == 0 {
      access.push({object:id,properties:[(85U,None),(117U,None),(77U,None)]})
    }
  }
  access.push({object:@bac.ObjectId::new(0,999),properties:[(85U,None)]})
  let response = @support.transact(server,client,14,@bac.encode_read_multiple(access),2UL)
  let results = match response {
    Completed(ComplexAck(_,14,body)) => @bac.decode_multiple_ack(body)
    _ => raise Failure("batch read failed")
  }
  let mut total = 0.0
  let mut missing = 0
  for entry in results {
    for result in entry.results {
      match result {
        PropertyData(r,[Application(Real(value))]) if r.property == 85U => total += value.to_double()
        PropertyData(r,[Application(Enumerated(unit))]) if r.property == 117U => assert_eq(unit,19U)
        PropertyFailure(_,1U,31U) => missing += 1
        PropertyData(_,_) => ()
        _ => raise Failure("unexpected meter result")
      }
    }
  }
  assert_eq(total,3600.0)
  assert_eq(missing,1)
  println("Energy: discovered gateway, enumerated 8 typed meter points, RPM sum 3600 kWh and isolated one missing-object error")
}



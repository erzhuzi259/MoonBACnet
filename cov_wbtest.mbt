test "COV initial notification threshold baseline renewal and status changes" {
  let d = sample_device()
  let id = ObjectId::new(0,1)
  d.update(id,22U,Real(1.0F))
  let cov = CovManager::new(d)
  let sub : SubscribeCov = {process:7U,object:id,confirmed:Some(false),lifetime:Some(100U)}
  cov.subscribe("observer",sub,0UL)
  let initial = cov.poll(0UL)
  assert_eq(initial.length(),1)
  assert_eq(initial[0].notification.remaining,100U)
  assert_eq(cov.poll(1UL).length(),0)
  d.update(id,85U,Real(20.6F))
  assert_eq(cov.poll(2UL).length(),0)
  d.update(id,85U,Real(21.0F))
  assert_eq(cov.poll(3UL).length(),1)
  d.update(id,111U,Bits(4,b"\x80"))
  assert_eq(cov.poll(4UL).length(),1)
  cov.subscribe("observer",sub,5UL)
  assert_eq(cov.poll(5UL)[0].notification.remaining,100U)
  expect_error(() => { ignore(cov.poll(4UL)) })
}

test "COV expiry cancellation perpetual and peer process object subscription identity" {
  let d = sample_device()
  let id = ObjectId::new(0,1)
  let cov = CovManager::new(d)
  let sub : SubscribeCov = {process:1U,object:id,confirmed:Some(false),lifetime:Some(2U)}
  cov.subscribe("a",sub,0UL)
  cov.subscribe("b",{ ..sub,lifetime:Some(0U) },0UL)
  cov.subscribe("a",{ ..sub,process:2U },0UL)
  assert_eq(cov.count(1UL),3)
  assert_eq(cov.count(2UL),1)
  assert_eq(cov.poll(3UL)[0].notification.remaining,0U)
  cov.subscribe("b",{ ..sub,confirmed:None,lifetime:None },4UL)
  assert_eq(cov.count(4UL),0)
  cov.subscribe("unknown",{ ..sub,confirmed:None,lifetime:None },4UL)
  expect_error(() => { cov.subscribe("a",{ ..sub,confirmed:Some(true) },4UL) })
  expect_error(() => { cov.subscribe("a",{ ..sub,object:d.identifier() },4UL) })
}

test "COV snapshot isolation prevents notification consumer mutation changing baseline" {
  let d = sample_device()
  let id = ObjectId::new(0,1)
  let cov = CovManager::new(d)
  cov.subscribe("a",{process:1U,object:id,confirmed:Some(false),lifetime:Some(0U)},0UL)
  let notifications = cov.poll(0UL)
  notifications[0].notification.values[0].value.clear()
  assert_eq(cov.poll(1UL).length(),0)
}

test "COV subscription limits and deadline overflow are explicit" {
  let d = Device::new(1,"d",1U,limits={ ..Limits::default(),max_subscriptions:1 })
  let id = ObjectId::new(0,1)
  d.add_point(id,"t",Analog,Real(0.0F))
  let cov = CovManager::new(d)
  let sub : SubscribeCov = {process:1U,object:id,confirmed:Some(false),lifetime:Some(0U)}
  cov.subscribe("a",sub,0UL)
  expect_error(() => { cov.subscribe("b",sub,0UL) })
  assert_eq(cov.count(0UL),1)
  expect_error(() => { cov.subscribe("a",{ ..sub,lifetime:Some(2U) },18446744073709551614UL) })
  assert_eq(cov.count(18446744073709551615UL),1)
}

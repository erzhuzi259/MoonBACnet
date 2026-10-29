priv struct Subscription {
  peer : String
  process : UInt
  object : ObjectId
  mut expires : UInt64?
  mut baseline : Array[Tag]?
}

pub(all) struct CovEnvelope {
  peer : String
  notification : CovNotification
} derive(Debug)

pub struct CovManager {
  priv device : Device
  priv subscriptions : Array[Subscription]
  priv mut now : UInt64
}

pub fn CovManager::new(device : Device) -> CovManager {
  { device, subscriptions: [], now: 0UL }
}

fn CovManager::advance(self : CovManager, now : UInt64) -> Unit raise BacnetError {
  if now < self.now { raise State("host clock moved backwards") }
  self.now = now
  for i = self.subscriptions.length()-1; i >= 0; i = i - 1 {
    if self.subscriptions[i].expires is Some(deadline) && deadline <= now {
      self.subscriptions.remove(i) |> ignore
    }
  }
}

pub fn CovManager::count(self : CovManager, now : UInt64) -> Int raise BacnetError {
  self.advance(now)
  self.subscriptions.length()
}

pub fn CovManager::subscribe(self : CovManager, peer : String, request : SubscribeCov, now : UInt64) -> Unit raise BacnetError {
  self.advance(now)
  ignore(encode_subscribe_cov(request, limits=self.device.limits))
  if peer.is_empty() || text_bytes(peer, 256).length() > 256 { raise Invalid("subscription peer", 0) }
  let object = self.device.find(request.object)
  ignore(self.device.point_domain(object))
  ignore(object.find(85U))
  if request.confirmed == Some(true) { raise Unsupported("confirmed COV delivery") }
  let mut found = -1
  for i = 0; i < self.subscriptions.length(); i = i + 1 {
    let s = self.subscriptions[i]
    if s.peer == peer && s.process == request.process && s.object == request.object { found = i; break }
  }
  if request.confirmed == None {
    if found >= 0 { self.subscriptions.remove(found) |> ignore }
    return
  }
  let lifetime = request.lifetime.unwrap_or(0U).to_uint64()
  if lifetime > 18446744073709551615UL-now { raise State("COV deadline overflow") }
  let expires = if lifetime == 0UL { None } else { Some(now+lifetime) }
  if found >= 0 {
    self.subscriptions[found].expires = expires
    self.subscriptions[found].baseline = None
  } else {
    if self.subscriptions.length() >= self.device.limits.max_subscriptions { raise Limit("subscription count") }
    self.subscriptions.push({ peer, process: request.process, object: request.object, expires, baseline: None })
  }
}

fn Device::cov_values(self : Device, id : ObjectId) -> Array[Tag] raise BacnetError {
  let value = self.read({ object: id, property: 85U, index: None })
  let status = self.read({ object: id, property: 111U, index: None })
  [Constructed(0, value), Constructed(1, status)]
}

fn Device::cov_changed(self : Device, id : ObjectId, baseline : Array[Tag], current : Array[Tag]) -> Bool raise BacnetError {
  if encode_tags(baseline, limits=self.limits) == encode_tags(current, limits=self.limits) { return false }
  match (baseline[:], current[:]) {
    ([Constructed(0, [Application(Real(old))]), Constructed(1, old_status)],
      [Constructed(0, [Application(Real(new))]), Constructed(1, new_status)]) => {
      if encode_tags(old_status, limits=self.limits) != encode_tags(new_status, limits=self.limits) { return true }
      let increment = match self.find(id).find(22U).values[:] {
        [Application(Real(v))] => v
        _ => raise State("missing analog COV increment")
      }
      let delta = new.to_double()-old.to_double()
      (if delta < 0.0 { -delta } else { delta }) >= increment.to_double()
    }
    _ => true
  }
}

pub fn CovManager::poll(self : CovManager, now : UInt64) -> Array[CovEnvelope] raise BacnetError {
  self.advance(now)
  let output : Array[CovEnvelope] = []
  let updates : Array[(Subscription, Array[Tag])] = []
  let mut bytes = 0
  for subscription in self.subscriptions {
    let current = self.device.cov_values(subscription.object)
    let changed = match subscription.baseline {
      None => true
      Some(old) => self.device.cov_changed(subscription.object, old, current)
    }
    if !changed { continue }
    let values : Array[CovProperty] = match current[:] {
      [Constructed(0, value), Constructed(1, status)] => [
        { property: 85U, index: None, value, priority: None },
        { property: 111U, index: None, value: status, priority: None },
      ]
      _ => raise State("COV snapshot shape")
    }
    let remaining = match subscription.expires {
      None => 0U
      Some(deadline) => (deadline-now).to_uint()
    }
    let notification : CovNotification = { process: subscription.process, device: self.device.id,
      object: subscription.object, remaining, values }
    let wire = encode_cov(notification, limits=self.device.limits)
    if wire.length() > self.device.limits.max_bytes-bytes { raise Limit("notification batch bytes") }
    bytes += wire.length()
    output.push({ peer: subscription.peer, notification })
    updates.push((subscription, clone_tags(current, self.device.limits)))
  }
  for (subscription, snapshot) in updates { subscription.baseline = Some(snapshot) }
  output
}

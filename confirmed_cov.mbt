///|
priv struct CovPending {
  peer : String
  process : UInt32
  object : ObjectId
  invoke : Int32
}

///|
fn CovManager::confirmed_subscription(
  self : CovManager,
  peer : String,
  process : UInt32,
  object : ObjectId,
) -> Subscription? {
  for subscription in self.subscriptions {
    if subscription.peer == peer &&
      subscription.process == process &&
      subscription.object == object &&
      subscription.confirmed {
      return Some(subscription)
    }
  }
  None
}

///|
fn Server::cleanup_cov(self : Server, now : UInt64) -> Unit raise BacnetError {
  self.cov.advance(now)
  if self.cov_client is Some(client) {
    for i = self.cov_pending.length() - 1; i >= 0; i = i - 1 {
      let pending = self.cov_pending[i]
      if self.cov.confirmed_subscription(
          pending.peer,
          pending.process,
          pending.object,
        )
        is None {
        ignore(client.cancel(pending.peer, pending.invoke))
      }
      if !client.pending.any(request => {
          request.peer == pending.peer &&
          request.request.invoke == pending.invoke
        }) {
        self.cov_pending.remove(i) |> ignore
      }
    }
  }
}

///|
/// Emit new confirmed notifications and due retries. Call Server::notifications
/// separately for unconfirmed subscriptions. Feed acknowledgements to handle/datagram.
pub fn Server::confirmed_notifications(
  self : Server,
  now : UInt64,
) -> Array[Transmission] raise BacnetError {
  self.clock(now)
  self.cleanup_cov(now)
  let client = match self.cov_client {
    Some(client) => client
    None => {
      let client = Client::new(limits=self.device.limits)
      self.cov_client = Some(client)
      client
    }
  }
  let changes = self.cov
    .poll_mode(now, true, commit=false)
    .filter(envelope => {
      !self.cov_pending.any(pending => {
        pending.peer == envelope.peer &&
        pending.process == envelope.notification.process &&
        pending.object == envelope.notification.object
      })
    })
  let started : Array[Transmission] = []
  {
    errdefer (for tx in started {
      ignore(client.cancel(tx.peer, tx.invoke))
    })
    for envelope in changes {
      started.push(
        client.start(
          envelope.peer,
          1,
          encode_cov(envelope.notification, limits=self.device.limits),
          now,
        ),
      )
    }
  }
  for i, envelope in changes {
    let notification = envelope.notification
    self.cov_pending.push({
      peer: envelope.peer,
      process: notification.process,
      object: notification.object,
      invoke: started[i].invoke,
    })
    let subscription = self.cov
      .confirmed_subscription(
        envelope.peer,
        notification.process,
        notification.object,
      )
      .unwrap()
    subscription.baseline = Some([
      Constructed(
        0,
        clone_tags(notification.values[0].value, self.device.limits),
      ),
      Constructed(
        1,
        clone_tags(notification.values[1].value, self.device.limits),
      ),
    ])
  }
  for event in client.poll(now) {
    match event {
      Retry(tx) => started.push(tx)
      TimedOut(_, _) => ()
    }
  }
  self.cleanup_cov(now)
  started
}

///|
fn Server::receive_notification(
  self : Server,
  peer : String,
  notification : CovNotification,
) -> Unit raise BacnetError {
  if peer.is_empty() {
    raise Invalid("COV notification peer", 0)
  }
  if self.received_notifications.length() >= self.device.limits.max_pending {
    raise Limit("received notification count")
  }
  let size = encode_cov(notification, limits=self.device.limits).length() +
    text_bytes(peer, 256).length()
  let mut retained = size
  for envelope in self.received_notifications {
    let cost = encode_cov(envelope.notification, limits=self.device.limits).length() +
      text_bytes(envelope.peer, 256).length()
    if cost > self.device.limits.max_bytes - retained {
      raise Limit("received notification bytes")
    }
    retained += cost
  }
  if retained > self.device.limits.max_bytes {
    raise Limit("received notification bytes")
  }
  self.received_notifications.push({ peer, notification, })
}

///|
/// Drain accepted notifications. Retransmitted confirmed messages share the
/// ordinary request cache and therefore do not enqueue a second event.
pub fn Server::take_notifications(self : Server) -> Array[CovEnvelope] {
  let result = self.received_notifications.copy()
  self.received_notifications.clear()
  result
}

///|
pub fn Server::notification_deadline(self : Server) -> UInt64? {
  match self.cov_client {
    Some(client) => client.next_deadline()
    None => None
  }
}

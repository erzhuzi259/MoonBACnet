pub(all) enum CommandDomain {
  Analog
  Binary
  MultiState(UInt)
} derive(Debug)

pub struct PriorityArray {
  priv domain : CommandDomain
  priv mut fallback : Value
  priv slots : Array[Value?]
}

fn domain_validate(domain : CommandDomain, value : Value) -> Unit raise BacnetError {
  let valid = match (domain, value) {
    (Analog, Real(v)) => (v.reinterpret_as_uint() & 0x7f800000U) != 0x7f800000U
    (Binary, Enumerated(v)) => v <= 1U
    (MultiState(count), Unsigned(v)) => count > 0U && v >= 1U && v <= count
    _ => false
  }
  if !valid { raise Property(2U, 9U) }
}

pub fn PriorityArray::new(domain : CommandDomain, fallback : Value) -> PriorityArray raise BacnetError {
  domain_validate(domain, fallback)
  { domain, fallback, slots: Array::make(16, None) }
}

pub fn PriorityArray::effective(self : PriorityArray) -> Value {
  for slot in self.slots { if slot is Some(value) { return value } }
  self.fallback
}

pub fn PriorityArray::active_priority(self : PriorityArray) -> Int? {
  for i = 0; i < 16; i = i + 1 { if self.slots[i] is Some(_) { return Some(i+1) } }
  None
}

pub fn PriorityArray::write(self : PriorityArray, priority : Int, value : Value) -> Unit raise BacnetError {
  if priority < 1 || priority > 16 || priority == 6 { raise Property(2U, 37U) }
  match value {
    Null => self.slots[priority-1] = None
    _ => { domain_validate(self.domain, value); self.slots[priority-1] = Some(value) }
  }
}

pub fn PriorityArray::set_default(self : PriorityArray, value : Value) -> Unit raise BacnetError {
  domain_validate(self.domain, value)
  self.fallback = value
}

pub fn PriorityArray::values(self : PriorityArray) -> Array[Tag] {
  self.slots.map(fn(slot) { Application(match slot { Some(v) => v; None => Null }) })
}

pub fn PriorityArray::default_value(self : PriorityArray) -> Value { self.fallback }

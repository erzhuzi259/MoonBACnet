///|
pub struct ObjectId {
  kind : Int32
  instance : Int32
} derive(Debug, Eq, Compare, Hash)

///|
pub fn ObjectId::new(
  kind : Int32,
  instance : Int32,
) -> ObjectId raise BacnetError {
  require_range(kind, 0, 1023, "object type")
  require_range(instance, 0, 4194303, "object instance")
  { kind, instance, }
}

///|
pub fn ObjectId::number(self : ObjectId) -> UInt32 {
  (self.kind.reinterpret_as_uint() << 22) | self.instance.reinterpret_as_uint()
}

///|
pub fn ObjectId::from_number(value : UInt32) -> ObjectId {
  {
    kind: (value >> 22).reinterpret_as_int(),
    instance: (value & 4194303U).reinterpret_as_int(),
  }
}

///|
pub(all) struct Date {
  year : Int32
  month : Int32
  day : Int32
  weekday : Int32
} derive(Debug, Eq)

///|
pub(all) struct Time {
  hour : Int32
  minute : Int32
  second : Int32
  hundredth : Int32
} derive(Debug, Eq)

///|
pub(all) enum Value {
  Null
  Boolean(Bool)
  Unsigned(UInt32)
  Signed(Int32)
  Real(Float)
  DoubleValue(Double)
  Octets(Bytes)
  Text(String)
  Bits(Int32, Bytes)
  Enumerated(UInt32)
  DateValue(Date)
  TimeValue(Time)
  Object(ObjectId)
} derive(Debug)

///|
pub(all) enum Tag {
  Application(Value)
  Context(Int32, Bytes)
  Constructed(Int32, Array[Tag])
} derive(Debug)

///|
fn date_valid(d : Date) -> Bool {
  (d.year >= 0 && d.year <= 255) &&
  ((d.month >= 1 && d.month <= 14) || d.month == 255) &&
  ((d.day >= 1 && d.day <= 34) || d.day == 255) &&
  ((d.weekday >= 1 && d.weekday <= 7) || d.weekday == 255)
}

///|
fn time_valid(t : Time) -> Bool {
  ((t.hour >= 0 && t.hour <= 23) || t.hour == 255) &&
  ((t.minute >= 0 && t.minute <= 59) || t.minute == 255) &&
  ((t.second >= 0 && t.second <= 59) || t.second == 255) &&
  ((t.hundredth >= 0 && t.hundredth <= 99) || t.hundredth == 255)
}

///|
fn bits_valid(unused : Int32, data : Bytes) -> Bool {
  if unused < 0 || unused > 7 {
    return false
  }
  if data.is_empty() {
    return unused == 0
  }
  let mask = (1 << unused) - 1
  (data[data.length() - 1].to_int() & mask) == 0
}

///|
pub extend ObjectId with @debug.Debug::{to_repr}

///|
pub extend ObjectId with Eq::{equal, not_equal}

///|
pub extend Date with @debug.Debug::{to_repr}

///|
pub extend Date with Eq::{equal, not_equal}

///|
pub extend Time with @debug.Debug::{to_repr}

///|
pub extend Time with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend Tag with @debug.Debug::{to_repr}

///|
pub extend ObjectId with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend ObjectId with Hash::{hash, hash_combine}

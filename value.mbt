pub struct ObjectId {
  kind : Int
  instance : Int
} derive(Debug, Eq, Compare, Hash)

pub fn ObjectId::new(kind : Int, instance : Int) -> ObjectId raise BacnetError {
  require_range(kind, 0, 1023, "object type")
  require_range(instance, 0, 4194303, "object instance")
  { kind, instance }
}

pub fn ObjectId::number(self : ObjectId) -> UInt {
  (self.kind.reinterpret_as_uint() << 22) | self.instance.reinterpret_as_uint()
}

pub fn ObjectId::from_number(value : UInt) -> ObjectId {
  { kind: (value >> 22).to_int(), instance: (value & 4194303U).to_int() }
}

pub(all) struct Date {
  year : Int
  month : Int
  day : Int
  weekday : Int
} derive(Debug, Eq)

pub(all) struct Time {
  hour : Int
  minute : Int
  second : Int
  hundredth : Int
} derive(Debug, Eq)

pub(all) enum Value {
  Null
  Boolean(Bool)
  Unsigned(UInt)
  Signed(Int)
  Real(Float)
  DoubleValue(Double)
  Octets(Bytes)
  Text(String)
  Bits(Int, Bytes)
  Enumerated(UInt)
  DateValue(Date)
  TimeValue(Time)
  Object(ObjectId)
} derive(Debug)

pub(all) enum Tag {
  Application(Value)
  Context(Int, Bytes)
  Constructed(Int, Array[Tag])
} derive(Debug)

fn date_valid(d : Date) -> Bool {
  (d.year >= 0 && d.year <= 255) &&
  ((d.month >= 1 && d.month <= 14) || d.month == 255) &&
  ((d.day >= 1 && d.day <= 34) || d.day == 255) &&
  ((d.weekday >= 1 && d.weekday <= 7) || d.weekday == 255)
}

fn time_valid(t : Time) -> Bool {
  ((t.hour >= 0 && t.hour <= 23) || t.hour == 255) &&
  ((t.minute >= 0 && t.minute <= 59) || t.minute == 255) &&
  ((t.second >= 0 && t.second <= 59) || t.second == 255) &&
  ((t.hundredth >= 0 && t.hundredth <= 99) || t.hundredth == 255)
}

fn bits_valid(unused : Int, data : Bytes) -> Bool {
  if unused < 0 || unused > 7 { return false }
  if data.is_empty() { return unused == 0 }
  let mask = (1 << unused) - 1
  (data[data.length()-1].to_int() & mask) == 0
}

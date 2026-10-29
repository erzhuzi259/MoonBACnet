priv struct Fields {
  tags : Array[Tag]
  mut pos : Int
}

fn Fields::new(tags : Array[Tag]) -> Fields { { tags, pos: 0 } }

fn Fields::next(self : Fields) -> Tag raise BacnetError {
  if self.pos >= self.tags.length() { raise Invalid("missing service field", self.pos) }
  let tag = self.tags[self.pos]
  self.pos += 1
  tag
}

fn Fields::context(self : Fields, number : Int) -> Bytes raise BacnetError {
  match self.next() {
    Context(n, bytes) if n == number => bytes
    _ => raise Invalid("context field order or type", self.pos-1)
  }
}

fn Fields::optional(self : Fields, number : Int) -> Bytes? {
  if self.pos < self.tags.length() && self.tags[self.pos] is Context(n, bytes) && n == number {
    self.pos += 1
    Some(bytes)
  } else { None }
}

fn Fields::uint(self : Fields, number : Int) -> UInt raise BacnetError {
  read_unsigned(self.context(number))
}

fn Fields::optional_uint(self : Fields, number : Int) -> UInt? raise BacnetError {
  match self.optional(number) { Some(b) => Some(read_unsigned(b)); None => None }
}

fn Fields::object(self : Fields, number : Int) -> ObjectId raise BacnetError {
  let bytes = self.context(number)
  if bytes.length() != 4 { raise Invalid("context object ID width", self.pos-1) }
  ObjectId::from_number(read_unsigned(bytes))
}

fn Fields::children(self : Fields, number : Int) -> Array[Tag] raise BacnetError {
  match self.next() {
    Constructed(n, tags) if n == number => tags
    _ => raise Invalid("expected constructed field", self.pos-1)
  }
}

fn Fields::done(self : Fields) -> Unit raise BacnetError {
  if self.pos != self.tags.length() { raise Invalid("unexpected service field", self.pos) }
}

fn context_uint(number : Int, value : UInt) -> Tag raise BacnetError {
  Context(number, unsigned_bytes(value))
}

fn context_object(number : Int, value : ObjectId) -> Tag raise BacnetError {
  let w = Writer::new(4)
  w.uint(value.number(), 4)
  Context(number, w.finish())
}

fn context_bool(number : Int, value : Bool) -> Tag {
  Context(number, if value { b"\x01" } else { b"\x00" })
}

fn read_context_bool(bytes : Bytes) -> Bool raise BacnetError {
  if bytes.length() != 1 || bytes[0].to_int() > 1 { raise Invalid("context boolean", 0) }
  bytes[0].to_int() == 1
}

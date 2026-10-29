///|
priv struct Budget {
  mut nodes : Int32
  limits : Limits
}

///|
fn Budget::visit(self : Budget, depth : Int32) -> Unit raise BacnetError {
  if depth > self.limits.max_depth || self.nodes >= self.limits.max_nodes {
    raise Limit("tag nesting or node count")
  }
  self.nodes += 1
}

///|
fn tag_header(
  w : Writer,
  number : Int32,
  context : Bool,
  lvt : Int32,
) -> Unit raise BacnetError {
  require_range(number, 0, 254, "tag number")
  let nibble = if number < 15 { number } else { 15 }
  w.u8((nibble << 4) | (if context { 8 } else { 0 }) | lvt)
  if number >= 15 {
    w.u8(number)
  }
}

///|
fn primitive_header(
  w : Writer,
  number : Int32,
  context : Bool,
  length : Int32,
) -> Unit raise BacnetError {
  if length < 0 {
    raise Invalid("negative length", 0)
  }
  tag_header(w, number, context, if length < 5 { length } else { 5 })
  if length >= 5 {
    if length <= 253 {
      w.u8(length)
    } else if length <= 65535 {
      w.u8(254)
      w.uint(length.reinterpret_as_uint(), 2)
    } else {
      w.u8(255)
      w.uint(length.reinterpret_as_uint(), 4)
    }
  }
}

///|
fn encode_tag(
  w : Writer,
  tag : Tag,
  b : Budget,
  depth : Int32,
) -> Unit raise BacnetError {
  b.visit(depth)
  match tag {
    Application(Boolean(value)) =>
      tag_header(w, 1, false, if value { 1 } else { 0 })
    Application(value) => {
      let (kind, body) = application_body(value, b.limits)
      primitive_header(w, kind, false, body.length())
      w.put(body)
    }
    Context(number, bytes) => {
      primitive_header(w, number, true, bytes.length())
      w.put(bytes)
    }
    Constructed(number, children) => {
      tag_header(w, number, true, 6)
      for child in children {
        encode_tag(w, child, b, depth + 1)
      }
      tag_header(w, number, true, 7)
    }
  }
}

///|
pub fn encode_tags(
  tags : Array[Tag],
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  limits.validate()
  let w = Writer::new(limits.max_bytes)
  let b : Budget = { nodes: 0, limits, }
  for tag in tags {
    encode_tag(w, tag, b, 0)
  }
  w.finish()
}

///|
fn decode_sequence(
  r : Reader,
  b : Budget,
  depth : Int32,
  closing : Int32?,
) -> Array[Tag] raise BacnetError {
  let result : Array[Tag] = []
  while r.remaining() > 0 {
    let start = r.pos
    let first = r.u8()
    let context = (first & 8) != 0
    let mut number = first >> 4
    let lvt = first & 7
    if number == 15 {
      number = r.u8()
      if number == 255 {
        raise Invalid("reserved extended tag", start)
      }
    }
    if context && lvt == 7 {
      if closing == Some(number) {
        return result
      }
      raise Invalid("mismatched closing tag", start)
    }
    b.visit(depth)
    if context && lvt == 6 {
      result.push(
        Constructed(number, decode_sequence(r, b, depth + 1, Some(number))),
      )
      continue
    }
    if !context && number == 1 {
      if lvt > 1 {
        raise Invalid("application boolean LVT", start)
      }
      result.push(Application(Boolean(lvt == 1)))
      continue
    }
    if lvt >= 6 {
      raise Invalid("application opening or closing tag", start)
    }
    let mut length = lvt
    if lvt == 5 {
      length = r.u8()
      if length == 254 {
        length = r.uint(2).reinterpret_as_int()
      } else if length == 255 {
        let wide = r.uint(4)
        if wide > b.limits.max_bytes.reinterpret_as_uint() {
          raise Limit("tag payload")
        }
        length = wide.reinterpret_as_int()
      }
    }
    let body = r.take(length)
    result.push(
      if context {
        Context(number, body)
      } else {
        Application(application_value(number, body, b.limits))
      },
    )
  }
  if closing != None {
    raise Invalid("missing closing tag", r.pos)
  }
  result
}

///|
pub fn decode_tags(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> Array[Tag] raise BacnetError {
  let r = Reader::new(data, limits)
  decode_sequence(r, { nodes: 0, limits, }, 0, None)
}

///|
fn clone_tags(
  tags : Array[Tag],
  limits : Limits,
) -> Array[Tag] raise BacnetError {
  decode_tags(encode_tags(tags, limits~), limits~)
}

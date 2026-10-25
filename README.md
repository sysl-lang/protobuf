# protobuf

Protocol Buffers for [sysl](https://github.com/sysl-lang/sysl), written in sysl and nothing else.

*An independent sysl package for Protocol Buffers. It is not affiliated with or endorsed by Protocol Buffers' authors or trademark holders.*

It holds:

- **a wire-format runtime** (`sh.sysl.protobuf`) — varints, zigzag, fixed-width words, length-delimited
  and packed fields, a writer into a slice you own that answers `Full` when it runs out, a growing
  writer over a `Buf[u8]`, and a reader that skips unknown fields of every wire type and names the byte
  offset of whatever was wrong. Encoding needs no heap and no operating system;
- **a `.proto` reader** (`sh.sysl.protobuf.schema`) — proto3 files read into a model with spans, imports
  found on a search path, every type name resolved the way protoc resolves it, and protoc's rules on
  numbers, names and enums enforced with diagnostics that quote the line;
- **a generator** (`sh.sysl.protobuf.gen`) — the model written out as sysl, one module per `.proto`
  package;
- **`protoc-sysl`**, a command a few lines long over the last two.

*An independent sysl package for Protocol Buffers. It is not affiliated with or endorsed by Protocol Buffers' authors or trademark holders.*

```
sh/sysl/protobuf/            the runtime: wire.sysl, output.sysl, reader.sysl, codec.sysl
sh/sysl/protobuf/schema/     the reader: model, parse, resolve, load
sh/sysl/protobuf/gen/        the generator, and the command line it runs
sh/sysl/protobuf/testdata/   scalars.sysl, generated from testdata/scalars.proto and checked in
testdata/                    the oracles' .proto files
tools/protoc-sysl/           the command
tools/portable/              the freestanding probe
```

## Using it

```hocon
dependencies {
  protobuf { git = "github.com/sysl-lang/protobuf", version = "0.1.1" }
}
```

Build the command and generate:

```
sysl build tools/protoc-sysl -o protoc-sysl
protoc-sysl -I proto --out src proto/demo/person.proto
```

```
usage: protoc-sysl [-I <dir>]... --out <dir> <file.proto>...

  -I, --proto_path <dir>   a directory imports are found under; may be repeated
  --out <dir>              where the generated files go
  --check                  write nothing; fail if any file under --out differs from what
                           would be generated
```

It exits 0 on success, 1 when a schema does not read or resolve (every diagnostic is printed), and 2
for a command line it cannot parse. Each file given is generated; an imported file is read but not
generated unless it is given too, so list every file of a package you want as sysl.

## What it generates

```proto
syntax = "proto3";

package demo;

message Person {
  string name = 1;
  int32 id = 2;
  repeated string emails = 3;

  enum PhoneType {
    PHONE_TYPE_UNSPECIFIED = 0;
    PHONE_TYPE_MOBILE = 1;
    PHONE_TYPE_HOME = 2;
  }

  oneof contact {
    string phone = 4;
    PhoneType preferred = 5;
  }
}
```

becomes `src/demo/person.sysl`:

```sysl
module demo

import sh.sysl.protobuf.{Codec, DecodeError, EncodeError, EnumOf, Int32, Message, MessageOf, Output, ProtoEnum, Reader, Str}
import sysl.buf.{Buf, buf}

struct Person derives Eq, Display
    name: string
    id: i32
    emails: Buf[string]
    contact: Option[PersonContact]

enum PersonContact derives Eq, Display
    Phone(v: string)
    Preferred(v: PersonPhoneType)

impl Message for Person
    empty() -> Person = Person("", 0, buf(), None)

    encoded_size(self) -> usize
        var n = Str.field_size(1, self.name)
        n += Int32.field_size(2, self.id)
        n += Str.repeated_size(3, self.emails.view())
        n += self.contact match
            Some(PersonContact.Phone(v)) -> Str.present_size(4, v)
            Some(PersonContact.Preferred(v)) -> EnumOf[PersonPhoneType].present_size(5, v)
            None -> 0
        n
    end encoded_size

    encode[O: Output](self, out: *O) -> Result[unit, EncodeError]
        out.field[Str](1, self.name)?
        out.field[Int32](2, self.id)?
        Str.repeated(out, 3, self.emails.view())?
        self.contact match
            Some(PersonContact.Phone(v)) -> Str.present(out, 4, v)?
            Some(PersonContact.Preferred(v)) -> out.present[EnumOf[PersonPhoneType]](5, v)?
            None -> ()
        Ok(())
    end encode

    merge(*self, r: *Reader) -> Result[unit, DecodeError]
        while r.more()
            val f = r.field()?
            f.number match
                1 -> self.name = Str.read(r, f)?
                2 -> self.id = Int32.read(r, f)?
                3 -> Str.read_repeated(r, f, self.emails)?
                4 -> self.contact = Some(PersonContact.Phone(Str.read(r, f)?))
                5 -> self.contact = Some(PersonContact.Preferred(EnumOf[PersonPhoneType].read(r, f)?))
                _ -> r.skip(f)?
        Ok(())
    end merge

enum PersonPhoneType derives Eq, Display
    Unspecified
    Mobile
    Home
    // A number this schema does not name, kept so that it is written back unchanged.
    Unrecognized(value: i32)
end PersonPhoneType

impl ProtoEnum for PersonPhoneType
    value -> i32 = self match
        Unspecified -> 0
        Mobile -> 1
        Home -> 2
        Unrecognized(v) -> v

    from_value(v: i32) -> PersonPhoneType = v match
        0 -> Unspecified
        1 -> Mobile
        2 -> Home
        _ -> Unrecognized(v)
```

and is used like this:

```sysl
import demo.{Person, PersonContact}
import sh.sysl.protobuf.{Message, slice_output}

var p = Person.empty()
p.name = "Ada"
p.emails.push("ada@example.com")
p.contact = Some(PersonContact.Phone("555"))

val bytes = p.to_bytes()                  // a growing Buf[u8]
val back = Person.decode(bytes.view())    // Result[Person, DecodeError]

var store: [64]u8 = [0; 64]               // or into storage you own, with no heap
var out = slice_output(store[..])
p.encode(&out)?                           // Err(Full(at)) when it does not fit
```

| `.proto` | sysl |
|---|---|
| `message M` | `struct M derives Eq, Display`, with `impl Message for M` |
| a message `I` nested in `M` | `struct MI` — sysl does not nest types, so the names are joined |
| `enum E` | `enum E`, its values camel-cased with `E`'s own prefix taken off, plus `Unrecognized(value: i32)` |
| `double`, `float` | `real`, `f32` |
| `int32`, `sint32`, `sfixed32` / `int64`, `sint64`, `sfixed64` | `i32` / `i64` |
| `uint32`, `fixed32` / `uint64`, `fixed64` | `u32` / `u64` |
| `bool`, `string`, `bytes` | `bool`, `string`, `Buf[u8]` |
| a message field, `optional T` | `Option[T]` |
| `repeated T` | `Buf[T]`, packed on the wire for numbers unless `[packed = false]` |
| `map<K, V> f` | `Buf[MFEntry]`, the entry message protoc defines, in wire order |
| `oneof o` | `o: Option[MO]`, an enum with one variant per member |
| a field named for a sysl reserved word | the word in backticks: `` `type` `` |
| a field named `encode`, `decode`, `merge`, `empty`, `encoded_size` or `to_bytes` | an underscore after it |

**Enums are open**: a number the schema does not name decodes to `Unrecognized(n)` and encodes back
as `n`, which is what proto3 requires. A value that aliases another (`allow_alias`) is not a second
variant; the first name is, and the generated enum says which names share it.

**A `Buf` is a handle**, as everywhere in sysl: copying a message copies its handles, so two copies
share their repeated fields. `decode` always makes fresh ones.

## Supported, and deliberately not

Read, resolved and generated: `syntax = "proto3"`, `package`, `import` (with `public` passed through
and `weak` accepted), messages nested to any depth, enums with `allow_alias` and negative values, all
fifteen scalar types, `repeated` (packed by default, `[packed = false]` honoured), `map<K, V>`, `oneof`,
`optional`, `reserved` numbers, ranges and names, `json_name`, comments of both kinds, and options of
every shape (kept as written on the model; only `packed`, `json_name` and `allow_alias` are acted on).
A `service` is read and nothing is generated for it.

- **proto2 and editions are refused**, each construct by name where it is written: a missing or
  `"proto2"` `syntax`, `required`, groups, `extensions` and `extend`.
- **Unknown fields are skipped, not kept**: they are read past correctly, of every wire type including
  groups, but re-encoding a message does not reproduce them.
- **A message that contains itself by value** — through a singular message field or a oneof member,
  directly or through others — is refused by the generator, since a sysl struct cannot hold itself.
  Recursion through `repeated` or a map works.
- **A oneof member that is a message, read twice, is replaced** rather than merged; a singular message
  field read twice is merged, as the format says.
- **No fixed-capacity generation yet** (nanopb's `max_count` / `max_size`): a generated message's
  `string`, `bytes` and repeated fields are heap-backed, so decoding one allocates. Encoding any message
  into a `SliceOutput` does not. This is the next piece of work.
- **No JSON mapping, no reflection, no services.**

## How it is checked

`sh scripts/gate.sh` runs `sysl test .` over the workspace, builds `tools/portable` for thumbv6m,
thumbv7em, thumb (v8-M), riscv32 and aarch64 freestanding, and builds the command. The tests:

- **protoc as the encoding oracle** (`gen/oracle_tests.sysl`). A value built in generated sysl and the
  same value in protobuf's text format: `protoc --encode` must give exactly the bytes `to_bytes` does,
  the generated `decode` must read protoc's bytes back to an equal value, and `encoded_size` must be the
  length. The cases cover every scalar type at zero, one, minus one, its maximum and its minimum (a
  negative `int32` is a ten-byte varint, `-0.0` is written, infinities), packed and unpacked repeated
  fields, nested messages, every member of a oneof (written even at its default), `optional`, open
  enums with unnamed numbers, aliases, maps (one entry byte for byte; several through `protoc --decode`,
  which prints a map sorted, since protoc writes a map in hash order), a message written twice and
  merged, a truncated message refused at its offset, and fields a message does not know.
- **protoc as the parser oracle** (`schema/oracle_tests.sysl`). `protoc --descriptor_set_out
  --include_imports` over a corpus, decoded with `protoc --decode=google.protobuf.FileDescriptorSet`,
  must give the same message, field, number, label, type, type name, JSON name, oneof, enum value and
  reserved range, in the same order, as this reader's model. The corpus has a type shadowing an outer
  one, names found outward from three levels in, qualified and fully qualified references, enum
  aliases and negative values, reserved ranges up to `max`, `json_name`, proto3 `optional`, maps of
  messages and a public import.
- **The generated code compiles and runs.** The corpus — four files in three packages — is generated
  into a fresh project, built and run with the compiler under test; the program's encodings must equal
  protoc's and decode back. The checked-in `sh/sysl/protobuf/testdata/scalars.sysl` must be exactly
  what the generator writes today.
- **nanopb was not used** as a second oracle: its pip package carries the generator but not the C
  runtime, so it would mean vendoring nanopb's C and options files.

**Mutations** made on purpose, each of which turns tests red: the zigzag shift (31 to 30), a varint's
continuation bit (0x80 to 0x40) in the writer and in the reader, a packed run's length off by one, the
tag's shift (3 to 2) in the writer and in the reader, a oneof member written under the next field
number, the scope search starting one level out, a qualified name continuing outward when its first
part was found, `-0.0` treated as a default, and a map entry's key and value left out at their
defaults.

## License

ISC — see `LICENSE`.

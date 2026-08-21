alias Hologram.Compiler.Encoder

# Encoding escapes the text of every string and atom it emits. That escaping grew the result
# with `<>` on the way out of a per-character recursion, which made it quadratic in the length
# of a binary:
#
#     10 KB      5 ms        160 KB     2.1 s
#     80 KB    426 ms        320 KB    11.2 s
#                            418 KB    21.0 s
#
# It is linear now. The sizes below are here so a return to the old shape reads as a curve
# rather than as one slow number. The last two scenarios cover what a plain ASCII string does
# not reach: text that is mostly non-ASCII, which no longer matches the escaping pattern at all,
# and a binary that is not valid UTF-8, which is walked byte by byte instead of scanned.

ascii_unit = ~s/Type.map([[Type.atom("module"), Type.bitstring("a b c")]]), /

build_ascii = fn byte_count ->
  ascii_unit
  |> String.duplicate(div(byte_count, byte_size(ascii_unit)) + 1)
  |> binary_part(0, byte_count)
end

# Not truncated to an exact size - cutting a multi-byte char in half would make the binary
# invalid and send it down the other path.
non_ascii = String.duplicate("日本語のテキスト ładne ", 8_000)

not_text = String.duplicate(<<0xFF, 0xFE>>, 100_000)

Benchee.run(
  %{
    "10 KB of text" => fn -> Encoder.encode_term!(build_ascii.(10_000)) end,
    "80 KB of text" => fn -> Encoder.encode_term!(build_ascii.(80_000)) end,
    "160 KB of text" => fn -> Encoder.encode_term!(build_ascii.(160_000)) end,
    "320 KB of text" => fn -> Encoder.encode_term!(build_ascii.(320_000)) end,
    "640 KB of text" => fn -> Encoder.encode_term!(build_ascii.(640_000)) end,
    "256 KB of non-ASCII text" => fn -> Encoder.encode_term!(non_ascii) end,
    "200 KB binary that is not text" => fn -> Encoder.encode_term!(not_text) end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.Encoder.encode_term!/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)

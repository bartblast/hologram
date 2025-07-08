defmodule Hologram.Server.CookieTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Server.Cookie

  describe "decode/1" do
    test "decodes a Hologram-encoded string" do
      encoded = "%Hg20AAAALaGVsbG8gd29ybGQ"
      result = Cookie.decode(encoded)

      assert result == "hello world"
    end

    test "decodes a Hologram-encoded existing atom" do
      encoded = "%Hg3cFaGVsbG8"
      result = Cookie.decode(encoded)

      assert result == :hello
    end

    test "raises ArgumentError when decoding a Hologram-encoded nonexistent atom" do
      expected_error_msg =
        build_argument_error_msg(1, "invalid or unsafe external representation of a term")

      assert_raise ArgumentError, expected_error_msg, fn ->
        # :nonexistent123
        Cookie.decode("%Hg3cObm9uZXhpc3RlbnQxMjM")
      end
    end

    test "decodes a Hologram-encoded map" do
      encoded = "%Hg3QAAAABdwNrZXltAAAABXZhbHVl"
      result = Cookie.decode(encoded)

      assert result == %{key: "value"}
    end

    test "returns plain string unchanged when no %H prefix" do
      plain_value = "plain_cookie_value"
      result = Cookie.decode(plain_value)

      assert result == plain_value
    end

    test "returns empty string unchanged" do
      result = Cookie.decode("")

      assert result == ""
    end

    test "raises ArgumentError when Base64 decoding fails" do
      invalid_encoded = "%HinvalidBase64!!!"
      expected_error_msg = ~s'non-alphabet character found: "!" (byte 33)'

      assert_error ArgumentError, expected_error_msg, fn ->
        Cookie.decode(invalid_encoded)
      end
    end

    test "raises ArgumentError when Erlang term decoding fails" do
      # Valid base64 but invalid binary term format
      invalid_encoded = "%H" <> Base.encode64("not_a_valid_erlang_term", padding: false)

      expected_error_msg =
        build_argument_error_msg(1, "invalid or unsafe external representation of a term")

      assert_error ArgumentError, expected_error_msg, fn ->
        Cookie.decode(invalid_encoded)
      end
    end
  end

  describe "encode/1" do
    test "encodes a string" do
      result = Cookie.encode("hello world")

      assert result == "%Hg20AAAALaGVsbG8gd29ybGQ"
    end

    test "encodes a non-string" do
      result = Cookie.encode([1, 2, 3])

      assert result == "%Hg2sAAwECAw"
    end

    test "encoding is deterministic" do
      term = %{user_id: 123, role: :admin}

      assert Cookie.encode(term) == Cookie.encode(term)
    end

    test "encoded value contains no padding characters" do
      # If padding was applied the result would have a "=" character
      result = Cookie.encode("Hologram")

      refute String.contains?(result, "=")
    end
  end
end

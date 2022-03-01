defmodule Hologram.Compiler.FormatterTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Formatter

  test "append_line_break/1" do
    result = Formatter.append_line_break("abc")
    assert result == "abc\n"
  end

  describe "maybe_append_new_expression/2" do
    test "empty string appended" do
      result = Formatter.maybe_append_new_expression("abc", "")
      assert result == "abc"
    end

    test "non-empty string appended to a string ending with a space" do
      result = Formatter.maybe_append_new_expression("abc ", "xyz")
      assert result == "abc xyz"
    end

    test "non-empty string appended to a string not ending with a space" do
      result = Formatter.maybe_append_new_expression("abc", "xyz")
      assert result == "abc xyz"
    end
  end

  describe "maybe_append_new_line/2" do
    test "empty string appended" do
      result = Formatter.maybe_append_new_line("abc", "")
      assert result == "abc"
    end

    test "non-empty string appended to a string ending with a newline" do
      result = Formatter.maybe_append_new_line("abc\n", "xyz")
      assert result == "abc\nxyz"
    end

    test "non-empty string appended to a string not ending with a newline" do
      result = Formatter.maybe_append_new_line("abc", "xyz")
      assert result == "abc\nxyz"
    end
  end

  describe "maybe_append_new_section/2" do
    test "empty string appended" do
      result = Formatter.maybe_append_new_section("abc", "")
      assert result == "abc"
    end

    test "non-empty string appended to a string ending with a double newline" do
      result = Formatter.maybe_append_new_section("abc\n\n", "xyz")
      assert result == "abc\n\nxyz"
    end

    test "non-empty string appended to a string not ending with a double newline" do
      result = Formatter.maybe_append_new_section("abc", "xyz")
      assert result == "abc\n\nxyz"
    end
  end
end

defmodule Hologram.ExJsConsistency.Erlang.FilenameTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/erlang/filename_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "basename/1" do
    test "path with multiple segments" do
      assert :filename.basename("path/to/file.txt") == "file.txt"
    end

    test "path with single segment" do
      assert :filename.basename("file.txt") == "file.txt"
    end

    test "path with absolute path" do
      assert :filename.basename("/absolute/path/to/file.txt") == "file.txt"
    end

    test "path ending with slash" do
      assert :filename.basename("path/to/dir/") == "dir"
    end

    test "root path" do
      assert :filename.basename("/") == ""
    end

    test "empty string" do
      assert :filename.basename("") == ""
    end

    test "path with multiple consecutive slashes" do
      assert :filename.basename("path//to//file.txt") == "file.txt"
    end

    test "path with only slashes" do
      assert :filename.basename("///") == ""
    end

    test "bitstring input" do
      assert :filename.basename("path/to/file.txt") == "file.txt"
    end

    test "binary with invalid UTF-8 bytes" do
      # <<0xFF, 0xFE>> is invalid UTF-8
      filename = <<"path/to/", 0xFF, 0xFE, ".txt">>

      # Should preserve raw bytes for the invalid UTF-8
      expected = <<0xFF, 0xFE, ".", "t", "x", "t">>

      assert :filename.basename(filename) == expected
    end

    test "atom input" do
      assert :filename.basename(:"path/to/file.txt") == ~c"file.txt"
    end

    test "empty list input" do
      assert :filename.basename([]) == []
    end

    test "non-empty iolist input" do
      assert :filename.basename([~c"path/to/", ?f, ?i, ?l, ?e, ~c".txt"]) == ~c"file.txt"
    end

    test "iolist with invalid UTF-8 bytes" do
      # Pure charlist: [112, 97, 116, 104, 47, 116, 111, 47, 0xFF, 0xFE, 46, 116, 120, 116]
      # "path/to/" + [0xFF, 0xFE] + ".txt"
      filename = [?p, ?a, ?t, ?h, ?/, ?t, ?o, ?/, 0xFF, 0xFE, ?., ?t, ?x, ?t]

      # Should return raw bytes as integers: [0xFF, 0xFE, ?., ?t, ?x, ?t]
      expected = [0xFF, 0xFE, ?., ?t, ?x, ?t]

      assert :filename.basename(filename) == expected
    end

    test "charlist with only slashes" do
      assert :filename.basename([?/, ?/, ?/]) == []
    end

    test "raises FunctionClauseError if the argument is not a bitstring or atom or list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.basename(123) end
    end

    test "raises FunctionClauseError if the argument is a non-binary bitstring" do
      arg = <<1::1, 0::1, 1::1>>

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [arg, []]),
                   fn -> :filename.basename(arg) end
    end
  end

  describe "basename/2" do
    test "removes matching extension from basename" do
      assert :filename.basename("src/core/main.erl", ".erl") == "main"
    end

    test "removes matching extension from simple filename" do
      assert :filename.basename("file.txt", ".txt") == "file"
    end

    test "removes matching extension from path" do
      assert :filename.basename("/path/to/file.txt", ".txt") == "file"
    end

    test "removes multi-part extension" do
      assert :filename.basename("file.tar.gz", ".tar.gz") == "file"
    end

    test "removes partial extension when multiple exist" do
      assert :filename.basename("file.tar.gz", ".gz") == "file.tar"
    end

    test "returns basename when extension does not match" do
      assert :filename.basename("noextension", ".txt") == "noextension"
    end

    test "returns basename when extension partially matches" do
      assert :filename.basename("file.txt", "x") == "file.txt"
    end

    test "handles root path" do
      assert :filename.basename("/", "x") == ""
    end

    test "handles empty filename" do
      assert :filename.basename("", ".txt") == ""
    end

    test "removes extension from double-dotted filename" do
      assert :filename.basename("file.txt.txt", ".txt") == "file.txt"
    end

    test "removes extension that equals the entire basename" do
      assert :filename.basename(".hidden", ".hidden") == ""
    end

    test "handles charlist filename and extension" do
      assert :filename.basename(~c"file.txt", ~c".txt") == ~c"file"
    end

    test "handles charlist with path" do
      assert :filename.basename(~c"path/to/file.erl", ~c".erl") == ~c"file"
    end

    test "handles atom filename and extension" do
      assert :filename.basename(:"file.txt", :".txt") == ~c"file"
    end

    test "returns empty list for root with charlist" do
      assert :filename.basename(~c"/", ~c"x") == []
    end

    test "handles iolist filename" do
      assert :filename.basename([~c"path/to/", ?f, ?i, ?l, ?e, ~c".txt"], ".txt") ==
               "file"
    end

    test "returns basename when extension is longer than basename" do
      assert :filename.basename("a.b", ".longer") == "a.b"
    end

    test "handles mixed binary and charlist" do
      assert :filename.basename("path/to/file.erl", ~c".erl") == "file"
    end

    test "handles extension with no dot" do
      assert :filename.basename("file.txt", "txt") == "file."
    end

    test "handles empty extension - returns full basename" do
      assert :filename.basename("file.txt", "") == "file.txt"
    end

    test "handles path with trailing slash" do
      assert :filename.basename("path/to/dir/", ".txt") == "dir"
    end

    test "handles multiple consecutive slashes" do
      assert :filename.basename("path//to//file.txt", ".txt") == "file"
    end

    test "handles only slashes" do
      assert :filename.basename("///", "x") == ""
    end

    test "handles hidden file with extension" do
      assert :filename.basename(".hidden.txt", ".txt") == ".hidden"
    end

    test "handles file with only dot as name" do
      assert :filename.basename(".", ".") == ""
    end

    test "handles file with double dots" do
      assert :filename.basename("..", ".") == "."
    end

    test "handles long extension" do
      assert :filename.basename("archive.tar.gz.bak", ".tar.gz.bak") == "archive"
    end

    test "matches binary/charlist mismatch - binary filename, charlist ext" do
      assert :filename.basename("file.erl", ~c".erl") == "file"
    end

    test "matches charlist filename, binary ext" do
      assert :filename.basename(~c"file.erl", ".erl") == "file"
    end

    test "returns basename when extension equals basename" do
      assert :filename.basename("file", "file") == ""
    end

    test "handles iolist with mixed types" do
      assert :filename.basename(
               [~c"path/to/", ?f, ?i, ?l, ?e, ~c".erl"],
               ~c".erl"
             ) == ~c"file"
    end

    test "handles case-sensitive extension matching" do
      assert :filename.basename("file.TXT", ".txt") == "file.TXT"
    end

    test "handles multi-byte UTF-8 characters in filename" do
      assert :filename.basename("文件.txt", ".txt") == "文件"
    end

    test "handles multi-byte UTF-8 characters in extension" do
      assert :filename.basename("file.日本", ".日本") == "file"
    end

    test "handles path with dot in directory name but not matching extension" do
      assert :filename.basename("path.dir/file.txt", ".dir") == "file.txt"
    end

    test "returns charlist when basename/1 returns charlist and no match" do
      result = :filename.basename(~c"path/to/noextension", ~c".txt")
      expected = :filename.basename(~c"path/to/noextension")

      assert result == expected
    end

    test "handles empty charlist extension" do
      assert :filename.basename(~c"file.txt", ~c"") == ~c"file.txt"
    end

    test "raises FunctionClauseError if filename is invalid" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.basename(123, ".txt") end
    end

    test "raises FunctionClauseError if extension is invalid" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.basename("file.txt", 123) end
    end
  end

  describe "extension/1" do
    test "file with extension" do
      assert :filename.extension("foo.erl") == ".erl"
    end

    test "file without extension" do
      assert :filename.extension("foo") == ""
    end

    test "file with path and extension" do
      assert :filename.extension("path/to/file.txt") == ".txt"
    end

    test "file with multiple dots in filename" do
      assert :filename.extension("archive.tar.gz") == ".gz"
    end

    test "file starting with dot" do
      assert :filename.extension(".hidden") == ""
    end

    test "directory path without extension" do
      assert :filename.extension("beam.src/kalle") == ""
    end

    test "absolute path with extension" do
      assert :filename.extension("/usr/local/foo.txt") == ".txt"
    end

    test "empty string" do
      assert :filename.extension("") == ""
    end

    test "path with trailing slash" do
      assert :filename.extension("path/to/dir/") == ""
    end

    test "file with dot in directory name" do
      assert :filename.extension("path.dir/file") == ""
    end

    test "file with multiple dots including in directory" do
      assert :filename.extension("path.dir/file.tar.gz") == ".gz"
    end

    test "atom input with extension" do
      assert :filename.extension(:"file.txt") == ~c".txt"
    end

    test "atom input without extension" do
      assert :filename.extension(:file) == ~c""
    end

    test "empty list input" do
      assert :filename.extension([]) == []
    end

    test "iolist input with extension" do
      assert :filename.extension([~c"path/to/", ?f, ?i, ?l, ?e, ~c".txt"]) == ~c".txt"
    end

    test "bitstring input" do
      assert :filename.extension("file.txt") == ".txt"
    end

    test "handles invalid UTF-8 binary" do
      filename = <<255, 46, 254>>

      assert :filename.extension(filename) == <<46, 254>>
    end

    test "handles invalid UTF-8 iolist" do
      filename = [255, 46, 254]

      assert :filename.extension(filename) == [46, 254]
    end

    test "trailing dot is a valid extension" do
      assert :filename.extension("file.") == "."
    end

    test "hidden file with extension" do
      assert :filename.extension(".hidden.txt") == ".txt"
    end

    test "double dot" do
      assert :filename.extension("..") == "."
    end

    test "root path" do
      assert :filename.extension("/") == ""
    end

    test "current directory" do
      assert :filename.extension(".") == ""
    end

    test "raises FunctionClauseError if the argument is not a bitstring or atom or list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.extension(123) end
    end

    test "raises FunctionClauseError if the argument is a non-binary bitstring" do
      arg = <<1::1, 0::1, 1::1>>

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [arg, []]),
                   fn -> :filename.extension(arg) end
    end
  end

  describe "flatten/1" do
    test "binary" do
      filename = "path/to/file.txt"

      assert :filename.flatten(filename) == filename
    end

    test "atom" do
      assert :filename.flatten(:myfile) == ~c"myfile"
    end

    test "flat list of integers" do
      filename = [112, 97, 116, 104]

      assert :filename.flatten(filename) == filename
    end

    test "flat list of bitstrings" do
      filename = [<<"foo">>, <<"bar">>]

      assert :filename.flatten(filename) == filename
    end

    test "flat list of atoms" do
      # ?f = 102, ?o = 111, ?全 = 20840, ?息 = 24687, ?图 = 22270, ?b = 98, ?a = 97, ?r = 114
      assert :filename.flatten([:foo, :全息图, :bar]) == [
               102,
               111,
               111,
               20_840,
               24_687,
               22_270,
               98,
               97,
               114
             ]
    end

    test "nested list of integers" do
      assert :filename.flatten([112, [97, 116], 104]) == [112, 97, 116, 104]
    end

    test "deeply nested list of integers" do
      assert :filename.flatten([[[97, 98], 99], 100]) == [97, 98, 99, 100]
    end

    test "empty list" do
      assert :filename.flatten([]) == []
    end

    test "list with an empty list element" do
      assert :filename.flatten([97, [], 98]) == [97, 98]
    end

    test "mixed list with bitstrings, atoms, integers and nested lists" do
      # ?t = 116, ?o = 111
      assert :filename.flatten([<<"path">>, [47, :to], 63, [<<"file.txt">>]]) ==
               [<<"path">>, 47, 116, 111, 63, <<"file.txt">>]
    end

    test "raises FunctionClauseError if the argument is not a binary, atom, or list" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.flatten(123) end
    end

    test "raises FunctionClauseError if the argument is a non-binary bitstring" do
      arg = <<1::1, 0::1, 1::1>>

      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [arg, []]),
                   fn -> :filename.flatten(arg) end
    end
  end

  describe "split/1" do
    test "absolute Unix path" do
      assert :filename.split("/usr/local/bin") == ["/", "usr", "local", "bin"]
    end

    test "relative Unix path" do
      assert :filename.split("foo/bar") == ["foo", "bar"]
    end

    test "single component" do
      assert :filename.split("foo") == ["foo"]
    end

    test "root path" do
      assert :filename.split("/") == ["/"]
    end

    test "empty string" do
      assert :filename.split("") == []
    end

    test "multiple consecutive slashes" do
      assert :filename.split("//") == ["/"]
    end

    test "dot component" do
      assert :filename.split(".") == ["."]
    end

    test "double dot component" do
      assert :filename.split("..") == [".."]
    end

    test "path with dot in middle" do
      assert :filename.split("/./") == ["/", "."]
    end

    test "path with double dot in middle" do
      assert :filename.split("/../") == ["/", ".."]
    end

    test "relative path with dot prefix" do
      assert :filename.split("./foo") == [".", "foo"]
    end

    test "relative path with double dot prefix" do
      assert :filename.split("../foo") == ["..", "foo"]
    end

    test "path with dot in middle components" do
      assert :filename.split("foo/./bar") == ["foo", ".", "bar"]
    end

    test "path with double dot in middle components" do
      assert :filename.split("foo/../bar") == ["foo", "..", "bar"]
    end

    test "path with trailing slash" do
      assert :filename.split("foo/bar/") == ["foo", "bar"]
    end

    test "absolute path with trailing slash" do
      assert :filename.split("/foo/bar/") == ["/", "foo", "bar"]
    end

    test "path with multiple consecutive slashes in middle" do
      assert :filename.split("foo//bar") == ["foo", "bar"]
    end

    test "drive letter with colon and forward slash" do
      assert :filename.split("a:/msdev/include") == ["a:", "msdev", "include"]
    end

    test "charlist input" do
      assert :filename.split(~c"foo/bar") == [~c"foo", ~c"bar"]
    end

    test "charlist input with absolute path" do
      assert :filename.split(~c"/usr/local/bin") == [~c"/", ~c"usr", ~c"local", ~c"bin"]
    end

    test "atom input" do
      assert :filename.split(:"foo/bar") == [~c"foo", ~c"bar"]
    end

    test "empty list input" do
      assert :filename.split([]) == []
    end

    test "iolist input" do
      assert :filename.split([~c"foo", ?/, ~c"bar"]) == [~c"foo", ~c"bar"]
    end

    test "binary with invalid UTF-8 bytes" do
      # <<0xFF, 0xFE>> is invalid UTF-8
      filename = <<"usr/", 0xFF, 0xFE, "/bin">>

      # Should preserve invalid UTF-8 bytes
      expected = ["usr", <<0xFF, 0xFE>>, "bin"]

      assert :filename.split(filename) == expected
    end

    test "iolist with invalid UTF-8 bytes" do
      # Pure charlist: [117, 115, 114, 47, 0xFF, 0xFE, 47, 98, 105, 110]
      # "usr/" + [0xFF, 0xFE] + "/bin"
      filename = [?u, ?s, ?r, ?/, 0xFF, 0xFE, ?/, ?b, ?i, ?n]

      # Should return raw bytes as integers: [[117, 115, 114], [0xFF, 0xFE], [98, 105, 110]]
      expected = [~c"usr", [0xFF, 0xFE], ~c"bin"]

      assert :filename.split(filename) == expected
    end

    test "raises FunctionClauseError if the argument is not a valid filename type" do
      assert_error FunctionClauseError,
                   build_function_clause_error_msg(":filename.do_flatten/2", [123, []]),
                   fn -> :filename.split(123) end
    end
  end
end

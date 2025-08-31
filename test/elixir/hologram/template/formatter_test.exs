defmodule Hologram.Template.FormatterTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Formatter
  alias Hologram.TemplateSyntaxError

  defp format_as_binary(t) do
    t
    |> format([])
    |> IO.iodata_to_binary()
  end

  describe "basic elements" do
    test "inline elements remain inline and normalize whitespace" do
      input = "<span>  abc  </span>"
      assert format_as_binary(input) == "<span> abc </span>"
    end

    test "block elements force newlines and indent" do
      input = "<div>abc</div>"

      expected =
        """
        <div>
          abc
        </div>
        """
        |> String.trim_trailing()

      assert format_as_binary(input) == expected
    end

    test "self-closing tags normalize whitespace" do
      input = "<MyComp   />"
      assert format_as_binary(input) == "<MyComp />"
    end

    test "empty elements" do
      assert format_as_binary("<div></div>") == "<div></div>"
      assert format_as_binary("<span></span>") == "<span></span>"
    end

    test "multiple block elements" do
      input = "<div>a</div><div>b</div>"

      expected =
        """
        <div>
          a
        </div>
        <div>
          b
        </div>
        """
        |> String.trim_trailing()

      assert format_as_binary(input) == expected
    end
  end

  describe "attributes" do
    test "normalize whitespace between attributes" do
      input = "<div id=\"test\" class=\"foo\"></div>"
      assert format_as_binary(input) == "<div id=\"test\" class=\"foo\"></div>"
    end

    test "boolean attributes" do
      input = "<script async src=\"test.js\"></script>"
      assert format_as_binary(input) == "<script async src=\"test.js\"></script>"
    end

    test "expression attributes" do
      input = "<div id={ @id }></div>"
      assert format_as_binary(input) == "<div id={@id}></div>"
    end

    test "long attribute lists break and indent" do
      input =
        "<div class=\"one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen\" id=\"test\" data-foo=\"bar\"></div>"

      formatted = format_as_binary(input)
      assert formatted =~ "\n  class="
      assert formatted =~ "\n  id="
      assert formatted =~ "\n  data-foo="
    end
  end

  describe "whitespace sensitivity" do
    test "significant whitespace in text nodes is preserved (normalized)" do
      input = "<div>Word1    Word2</div>"

      expected =
        """
        <div>
          Word1 Word2
        </div>
        """
        |> String.trim_trailing()

      assert format_as_binary(input) == expected
    end

    test "newlines in text nodes are treated as lines" do
      input = """
      <div>
        Line1
        Line2
      </div>
      """

      # We now preserve trailing newline from heredoc
      expected = "<div>\n  Line1\n  Line2\n</div>\n"
      assert format_as_binary(input) == expected
    end

    test "mixed content (text and inline tags)" do
      input = "<p>Please <a>click here</a> for more.</p>"

      expected =
        """
        <p>
          Please <a>click here</a> for more.
        </p>
        """
        |> String.trim_trailing()

      assert format_as_binary(input) == expected
    end

    test "long text nodes break and indent" do
      input =
        "<div>This is a very long text that should probably be wrapped if it exceeds eighty characters but currently it will just stay as one long line because it is returned as a single string document.</div>"

      formatted = format_as_binary(input)
      assert String.contains?(formatted, "\n  ")
      # It should have broken into multiple lines
      assert length(String.split(formatted, "\n")) > 3
    end
  end

  describe "blocks and logic" do
    test "block starts normalization" do
      input = "{%if   @show?   }abc{/if}"

      expected =
        """
        {%if @show?}
          abc
        {/if}
        """
        |> String.trim_trailing()

      assert format_as_binary(input) == expected
    end

    test "long Elixir expressions break and indent" do
      input =
        "<div>{ [:aaaaaaaaaa, :bbbbbbbbbb, :cccccccccc, :dddddddddd, :eeeeeeeeee, :ffffffffff, :gggggggggg, :hhhhhhhhhh] }</div>"

      formatted = format_as_binary(input)
      assert formatted =~ "\n      :aaaaaaaaaa,"
    end

    test "nested double curlies in expressions are fixed" do
      input = "{%if {@show?}}abc{/if}"

      expected =
        """
        {%if @show?}
          abc
        {/if}
        """
        |> String.trim_trailing()

      assert format_as_binary(input) == expected
    end

    test "deeply nested double curlies" do
      input = "<div>{ { { @value } } }</div>"

      expected =
        """
        <div>
          {@value}
        </div>
        """
        |> String.trim_trailing()

      assert format_as_binary(input) == expected
    end

    test "complex nested structure" do
      input = """
      <Layout>
        <Header title="My App" />
        {%if @user}
          <p>Welcome, {@user.name}!</p>
        {%else}
          <Link to=\"login\">Login</Link>
        {/if}
        <Footer />
      </Layout>
      """

      formatted = format_as_binary(input)
      assert formatted =~ "  <Header title=\"My App\" />"
      assert formatted =~ "  {%if @user}"
      # p is block now
      assert formatted =~ "    <p>\n      Welcome, {@user.name}!\n    </p>"
      assert formatted =~ "  {%else}"
      # Link is block now
      assert formatted =~ "    <Link to=\"login\">\n      Login\n    </Link>"
    end
  end

  describe "unparseable templates" do
    test "improper closing tag" do
      malformed = "<body><div>text</div</body>"
      assert_raise TemplateSyntaxError, fn -> format(malformed, []) end
    end

    test "unquoted attributes" do
      malformed = "<body><div id=test>text</div></body>"
      assert_raise TemplateSyntaxError, fn -> format(malformed, []) end
    end
  end

  describe "regressions" do
    test "empty template remains empty" do
      assert format_as_binary("") == ""
    end

    test "self-closing tag has single space" do
      assert format_as_binary("<slot />") == "<slot />"
      assert format_as_binary("<slot/>") == "<slot />"
    end

    test "self-closing tag with attributes" do
      assert format_as_binary("<div class=\"a\" />") == "<div class=\"a\" />"
    end

    test "raw blocks are preserved" do
      input = """
      {%raw}
        <div>{ @not_an_expression }</div>
      {/raw}
      """

      assert format_as_binary(input) == input
    end

    test "inviolable tags (script, style) are preserved" do
      input = """
      <script>
        if (a < b) {
          console.log("preserve");
        }
      </script>
      """

      assert format_as_binary(input) == input
    end
  end
end

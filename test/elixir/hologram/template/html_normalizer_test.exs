defmodule Hologram.Template.HTMLNormalizerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.HTMLNormalizer

  describe "children_context/3" do
    test "HTML element" do
      assert children_context("div", [], :html) == :html
    end

    test "SVG element" do
      assert children_context("g", [], :svg) == :svg
    end

    test "SVG HTML integration points" do
      assert children_context("foreignObject", [], :svg) == :html
      assert children_context("desc", [], :svg) == :html
      assert children_context("title", [], :svg) == :html
    end

    test "MathML element" do
      assert children_context("mrow", [], :math) == :math
    end

    test "MathML text integration points" do
      for tag_name <- ~w(mi mn mo ms mtext) do
        assert children_context(tag_name, [], :math) == :mathml_text
      end
    end

    test "annotation-xml element with an HTML encoding" do
      assert children_context("annotation-xml", [{"encoding", "text/html"}], :math) == :html

      assert children_context("annotation-xml", [{"encoding", "Application/XHTML+XML"}], :math) ==
               :html
    end

    test "annotation-xml element with another encoding" do
      assert children_context("annotation-xml", [{"encoding", "x"}], :math) == :annotation_xml
    end

    test "annotation-xml element without an encoding" do
      assert children_context("annotation-xml", [], :math) == :annotation_xml
    end
  end

  describe "element_namespace/2" do
    test "HTML context" do
      assert element_namespace("div", :html) == :html
      assert element_namespace("svg", :html) == :svg
      assert element_namespace("math", :html) == :math
    end

    test "SVG context" do
      assert element_namespace("p", :svg) == :svg
      assert element_namespace("math", :svg) == :svg
    end

    test "MathML context" do
      assert element_namespace("mi", :math) == :math
      assert element_namespace("svg", :math) == :math
    end

    test "annotation-xml context" do
      assert element_namespace("mi", :annotation_xml) == :math
      assert element_namespace("svg", :annotation_xml) == :svg
    end

    test "MathML text integration point context" do
      assert element_namespace("b", :mathml_text) == :html
      assert element_namespace("svg", :mathml_text) == :svg
      assert element_namespace("math", :mathml_text) == :math
      assert element_namespace("mglyph", :mathml_text) == :math
      assert element_namespace("malignmark", :mathml_text) == :math
    end
  end

  describe "normalize/3" do
    test "well-formed HTML passes through" do
      assert normalize(~s(<p class="big">Hologram</p>), "div", :html) ==
               ~s(<p class="big">Hologram</p>)
    end

    test "closes unclosed elements" do
      assert normalize("<div><b>bold", "p", :html) == "<div><b>bold</b></div>"
    end

    test "drops a stray end tag" do
      assert normalize("a</div>b", "div", :html) == "ab"
    end

    test "a stray </p> end tag opens an empty paragraph, as in the browser" do
      assert normalize("a</p>b", "div", :html) == "a<p></p>b"
    end

    test "keeps surrounding whitespace" do
      assert normalize("  <p>a</p>\n  ", "div", :html) == "  <p>a</p>\n  "
    end

    test "empty content" do
      assert normalize("", "div", :html) == ""
    end

    test "no parent tag name" do
      assert normalize("<p>a</p>", nil, :html) == "<p>a</p>"
    end

    test "escapes text and attribute values the way the parser decoded them" do
      html = ~s(&lt;b&gt; &amp; "q" <a title="x&quot;y" href="?a=1&amp;b=2">t</a>)

      assert normalize(html, "div", :html) ==
               ~s(&lt;b&gt; &amp; "q" <a title="x&quot;y" href="?a=1&amp;b=2">t</a>)
    end

    test "escapes no-break spaces in text and attribute values" do
      assert normalize(~s(a\u00A0b <a title="\u00A0">t</a>), "div", :html) ==
               ~s(a&nbsp;b <a title="&nbsp;">t</a>)
    end

    test "escapes angle brackets in attribute values" do
      assert normalize(~s(<a title="<x>">t</a>), "div", :html) == ~s(<a title="&lt;x&gt;">t</a>)
    end

    test "prints void elements without an end tag" do
      assert normalize("<p>a<br>b<img src=x></p>", "div", :html) ==
               ~s(<p>a<br>b<img src="x"></p>)
    end

    test "keeps the raw text of a style element" do
      html = ~s(<style>a > b { content: "&" }</style>)

      assert normalize(html, "div", :html) == html
    end

    # The parser drops a line feed right after these start tags, so one the content keeps is printed
    # with another in front of it.
    test "keeps a leading line feed in pre, textarea and listing elements" do
      html = "<pre>\n\nx</pre><textarea>\n\ny</textarea><listing>\n\nz</listing>"

      assert normalize(html, "div", :html) == html
    end

    test "keeps a leading line feed behind a dropped script element in a pre element" do
      assert normalize("<pre><script></script>\nx</pre>", "div", :html) == "<pre>\n\nx</pre>"
    end

    test "keeps a leading line feed behind a dropped range marker in a listing element" do
      assert normalize("<listing><!--hologram-html-->\nx</listing>", "div", :html) ==
               "<listing>\n\nx</listing>"
    end

    test "keeps a leading line feed in a pre element breaking out of SVG" do
      assert normalize("<pre>\n\nx</pre>", "svg", :svg) == "<pre>\n\nx</pre>"
    end

    test "keeps a leading line feed in a pre element inside an SVG foreignObject element" do
      html = "<svg><foreignObject><pre>\n\nx</pre></foreignObject></svg>"

      assert normalize(html, "div", :html) == html
    end

    test "adds no line feed to pre content that doesn't start with one" do
      assert normalize("<pre>x\n</pre>", "div", :html) == "<pre>x\n</pre>"
    end

    # A pre or a listing start tag breaks out of SVG, so a textarea is what stays foreign.
    test "adds no line feed to an SVG element named like textarea, whose leading one the parser keeps" do
      assert normalize("<textarea>\n\nx</textarea>", "svg", :svg) == "<textarea>\n\nx</textarea>"
    end

    test "escapes the text of a textarea element" do
      assert normalize("<textarea><b>&amp;</textarea>", "div", :html) ==
               "<textarea>&lt;b&gt;&amp;</textarea>"
    end

    test "nested table content under a non-table parent" do
      assert normalize("<table><td>x</table>", "div", :html) ==
               "<table><tbody><tr><td>x</td></tr></tbody></table>"
    end

    test "table rows under a non-table parent lose their tags, as in the browser" do
      assert normalize("<tr><td>cell</td></tr>", "div", :html) == "cell"
    end

    test "table rows under a tbody parent" do
      assert normalize("<tr><td>cell</td></tr>", "tbody", :html) == "<tr><td>cell</td></tr>"
    end

    test "table rows under a thead parent" do
      assert normalize("<tr><td>cell</td></tr>", "thead", :html) == "<tr><td>cell</td></tr>"
    end

    test "table rows under a tfoot parent" do
      assert normalize("<tr><td>cell</td></tr>", "tfoot", :html) == "<tr><td>cell</td></tr>"
    end

    test "table sections under a table parent" do
      assert normalize("<tbody><tr><td>cell</td></tr></tbody>", "table", :html) ==
               "<tbody><tr><td>cell</td></tr></tbody>"
    end

    test "table rows under a template parent" do
      assert normalize("<tr><td>cell</td></tr>", "template", :html) == "<tr><td>cell</td></tr>"
    end

    test "table cells under a tr parent" do
      assert normalize("<td>a</td><th>b</th>", "tr", :html) == "<td>a</td><th>b</th>"
    end

    test "columns under a colgroup parent" do
      assert normalize("<col span=2>", "colgroup", :html) == ~s(<col span="2">)
    end

    test "table rows under a table parent get the tbody the browser adds" do
      assert normalize("<tr><td>a</td></tr>", "table", :html) ==
               "<tbody><tr><td>a</td></tr></tbody>"
    end

    test "a caption and table rows under a table parent" do
      assert normalize("<caption>c</caption><tr><td>a</td></tr>", "table", :html) ==
               "<caption>c</caption><tbody><tr><td>a</td></tr></tbody>"
    end

    test "table cells under a tbody parent get the tr the browser adds" do
      assert normalize("<td>a</td><td>b</td>", "tbody", :html) ==
               "<tr><td>a</td><td>b</td></tr>"
    end

    test "text a table can't hold is moved before the table" do
      assert normalize("<tr><td>a</td></tr>b", "tbody", :html) == "b<tr><td>a</td></tr>"
    end

    test "a stray end tag for a table wrapper keeps the content after it" do
      assert normalize("<tr><td>a</td></tr></tbody><tr><td>b</td></tr>", "tbody", :html) ==
               "<tr><td>a</td></tr><tbody><tr><td>b</td></tr></tbody>"
    end

    test "a nested table under a table parent" do
      html = "<tr><td><table><tr><td>a</td></tr></table></td></tr>"

      assert normalize(html, "tbody", :html) ==
               "<tr><td><table><tbody><tr><td>a</td></tr></tbody></table></td></tr>"
    end

    test "an element a table can't hold is moved before the table" do
      assert normalize("<div>x</div><tr><td>a</td></tr>", "tbody", :html) ==
               "<div>x</div><tr><td>a</td></tr>"
    end

    test "table cells under a table parent get the tbody and the tr the browser adds" do
      assert normalize("<td>a</td>", "table", :html) == "<tbody><tr><td>a</td></tr></tbody>"
    end

    test "table cells under a thead parent get the tr the browser adds" do
      assert normalize("<th>a</th>", "thead", :html) == "<tr><th>a</th></tr>"
    end

    test "table cells under a tfoot parent get the tr the browser adds" do
      assert normalize("<td>a</td>", "tfoot", :html) == "<tr><td>a</td></tr>"
    end

    test "a column under a table parent gets the colgroup the browser adds" do
      assert normalize("<col span=2>", "table", :html) == ~s(<colgroup><col span="2"></colgroup>)
    end

    test "a stray end tag for the tr wrapper keeps the content after it" do
      assert normalize("<td>a</td></tr><td>b</td>", "tr", :html) ==
               "<td>a</td><tr><td>b</td></tr>"
    end

    test "a stray end tag for the template wrapper keeps the content after it" do
      assert normalize("<tr><td>a</td></tr></template><p>b</p>", "template", :html) ==
               "<tr><td>a</td></tr><p>b</p>"
    end

    test "a table the content opens under a table parent isn't taken for the wrapper" do
      assert normalize("<tr><td><table><tr><td>a</td></tr></table></td></tr>", "table", :html) ==
               "<tbody><tr><td><table><tbody><tr><td>a</td></tr></tbody></table></td></tr></tbody>"
    end

    test "SVG content keeps self-closed elements as siblings" do
      assert normalize(~s(<path d="a"/><path d="b"/>), "svg", :svg) ==
               ~s(<path d="a"></path><path d="b"></path>)
    end

    test "SVG content under a nested SVG parent" do
      assert normalize(~s(<circle r="1"/>), "g", :svg) == ~s(<circle r="1"></circle>)
    end

    test "SVG content keeps the case of SVG tag and attribute names" do
      html = ~s(<clipPath id="c"><rect viewBox="0 0 1 1"/></clipPath>)

      assert normalize(html, "svg", :svg) ==
               ~s(<clipPath id="c"><rect viewBox="0 0 1 1"></rect></clipPath>)
    end

    test "SVG content escapes the text of an SVG style element" do
      html = ~s(<style>a::after { content: "&lt;/svg&gt;" }</style>)

      assert normalize(html, "svg", :svg) == html
    end

    test "SVG content prints an SVG element named like an HTML void element with its content" do
      assert normalize("<source>a</source>", "svg", :svg) == "<source>a</source>"
    end

    test "an HTML start tag breaks out of the SVG wrapper, as in the browser" do
      assert normalize(~s(<circle r="1"/><p>a<br>b</p>), "g", :svg) ==
               ~s(<circle r="1"></circle><p>a<br>b</p>)
    end

    test "a stray end tag for the SVG wrapper keeps the content after it" do
      assert normalize(~s(<path d="a"/></svg><path d="b"/>), "g", :svg) ==
               ~s(<path d="a"></path><path d="b"></path>)
    end

    test "HTML inside an SVG foreignObject element" do
      html = "<svg><foreignObject><style>a > b {}</style><p>a<br>b</p></foreignObject></svg>"

      assert normalize(html, "div", :html) == html
    end

    test "HTML inside an SVG desc element" do
      assert normalize("<svg><desc><br></desc></svg>", "div", :html) ==
               "<svg><desc><br></desc></svg>"
    end

    test "MathML content escapes the text of a MathML style element" do
      html = "<math><style>&lt;/math&gt;</style></math>"

      assert normalize(html, "div", :html) == html
    end

    test "HTML inside a MathML text integration point" do
      assert normalize("<math><mtext><br></mtext></math>", "div", :html) ==
               "<math><mtext><br></mtext></math>"
    end

    test "HTML inside a MathML annotation-xml element with an HTML encoding" do
      html =
        ~s(<math><annotation-xml encoding="text/html"><br><style>a>b</style></annotation-xml></math>)

      assert normalize(html, "div", :html) == html
    end

    test "an HTML start tag breaks out of SVG content the content opens, as in the browser" do
      assert normalize("<div><svg><p>a<br>b</p></svg></div>", "div", :html) ==
               "<div><svg></svg><p>a<br>b</p></div>"
    end

    test "HTML inside an SVG title element" do
      assert normalize("<svg><title><br></title></svg>", "div", :html) ==
               "<svg><title><br></title></svg>"
    end

    test "an svg element below a MathML element that isn't an integration point is MathML" do
      html = "<math><mrow><svg><title><style>&lt;/math&gt;</style></title></svg></mrow></math>"

      assert normalize(html, "div", :html) == html
    end

    test "mglyph inside a MathML text integration point stays MathML" do
      html = "<math><mi><mglyph><style>&lt;/div&gt;</style></mglyph></mi></math>"

      assert normalize(html, "div", :html) == html
    end

    test "malignmark inside a MathML text integration point stays MathML" do
      html = "<math><mi><malignmark><style>&lt;/div&gt;</style></malignmark></mi></math>"

      assert normalize(html, "div", :html) == html
    end

    test "a math element inside SVG is SVG" do
      html = "<svg><math><mi><style>&lt;x&gt;</style></mi></math></svg>"

      assert normalize(html, "div", :html) == html
    end

    test "the encoding of an annotation-xml element is matched case-insensitively" do
      html = ~s(<math><annotation-xml encoding="TEXT/HTML"><br></annotation-xml></math>)

      assert normalize(html, "div", :html) == html
    end

    test "content of an annotation-xml element without an HTML encoding stays MathML" do
      html =
        ~s(<math><annotation-xml encoding="x"><mi><style>&lt;x&gt;</style></mi></annotation-xml></math>)

      assert normalize(html, "div", :html) == html
    end

    test "an svg element inside an annotation-xml element without an HTML encoding is SVG" do
      html =
        ~s(<math><annotation-xml encoding="x"><svg><style>&lt;x&gt;</style></svg></annotation-xml></math>)

      assert normalize(html, "div", :html) == html
    end

    test "MathML content under a MathML parent" do
      assert normalize("<mspace/><mi>x</mi>", "math", :math) == "<mspace></mspace><mi>x</mi>"
    end

    test "MathML content under a MathML parent escapes the text of a style element" do
      assert normalize("<style>&lt;/div&gt;</style>", "math", :math) ==
               "<style>&lt;/div&gt;</style>"
    end

    test "content under an annotation-xml parent without an HTML encoding" do
      assert normalize(
               ~s(<svg><circle r="1"/></svg><mi>x</mi>),
               "annotation-xml",
               :annotation_xml
             ) ==
               ~s(<svg><circle r="1"></circle></svg><mi>x</mi>)
    end

    test "content under a MathML text integration point parent" do
      assert normalize("<br>x", "mi", :mathml_text) == "<br>x"
    end

    test "keeps namespaced SVG attribute names" do
      html = ~s(<svg><use xlink:href="#a" xml:lang="en"></use></svg>)

      assert normalize(html, "div", :html) == html
    end

    test "keeps the raw text of xmp, iframe, noembed and noframes elements" do
      html = "<xmp>a<b</xmp><iframe>a<b</iframe><noembed>a<b</noembed><noframes>a<b</noframes>"

      assert normalize(html, "div", :html) == html
    end

    test "keeps a title and a meta element starting the content" do
      html = ~s(<title>t</title><meta charset="x"><p>a</p>)

      assert normalize(html, "div", :html) == html
    end

    test "drops script elements" do
      html = ~s[<p>x</p><script>alert(1)</script><script src="a.js"></script>]

      assert normalize(html, "div", :html) == "<p>x</p>"
    end

    test "drops nested script elements" do
      assert normalize("<div><p><script>1</script>a</p></div>", "div", :html) ==
               "<div><p>a</p></div>"
    end

    test "drops SVG script elements" do
      assert normalize(~s(<svg><script>1</script><circle r="1"/></svg>), "div", :html) ==
               ~s(<svg><circle r="1"></circle></svg>)
    end

    test "drops script elements inside a template element" do
      assert normalize("<template><script>1</script>t</template>", "div", :html) ==
               "<template>t</template>"
    end

    test "drops script elements under a table parent" do
      assert normalize("<tr><td><script>1</script>a</td></tr>", "tbody", :html) ==
               "<tr><td>a</td></tr>"
    end

    test "drops script elements under an SVG parent" do
      assert normalize(~s(<script>1</script><circle r="1"/>), "svg", :svg) ==
               ~s(<circle r="1"></circle>)
    end

    test "drops noscript elements" do
      assert normalize("a<noscript><p>b</p></noscript>c", "div", :html) == "ac"
    end

    test "drops a noscript element whose content would end it early in the browser" do
      html = "<noscript><!--</noscript><script>alert(1)</script>--></noscript>a"

      assert normalize(html, "div", :html) == "a"
    end

    test "drops plaintext elements" do
      assert normalize("a<plaintext>b</plaintext>c", "div", :html) == "a"
    end

    test "drops the shadowroot attributes of template elements" do
      html =
        ~s(<template id="t" shadowrootmode="open" shadowrootdelegatesfocus><p>a</p></template>)

      assert normalize(html, "div", :html) == ~s(<template id="t"><p>a</p></template>)
    end

    test "drops comments carrying a range marker and keeps other comments" do
      html = "a<!--hologram-html-->b<!--/hologram-html-->c<!-- keep -->"

      assert normalize(html, "div", :html) == "abc<!-- keep -->"
    end

    test "drops nested comments carrying a range marker" do
      assert normalize("<div><!--/hologram-html-->a</div>", "div", :html) == "<div>a</div>"
    end

    test "drops bogus comments carrying a range marker" do
      assert normalize("a<!hologram-html>b", "div", :html) == "ab"
    end
  end

  test "range_end_marker/0" do
    assert range_end_marker() == "/hologram-html"
  end

  test "range_start_marker/0" do
    assert range_start_marker() == "hologram-html"
  end
end

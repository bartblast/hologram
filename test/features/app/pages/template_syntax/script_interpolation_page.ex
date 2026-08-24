defmodule HologramFeatureTests.TemplateSyntax.ScriptInterpolationPage do
  use Hologram.Page

  route "/template-syntax/script-interpolation"

  layout HologramFeatureTests.Components.DefaultLayout

  # A closing script tag, an ampersand, each kind of quote, a template literal expression opener,
  # a backslash and a line break: everything the escaping has to carry through intact, and the one
  # sequence it must not let end the element.
  def init(_params, component, _server) do
    put_state(
      component,
      :value,
      ~s(</script><script>window.__xss = true</script> & "a" 'b' `c` ${d} e\\f\ng)
    )
  end

  # The script appends what it was given on each of its runs. A document load runs it once; a
  # second entry means the client's render of the same script differed from the server's, so the
  # boot patch rebuilt the element instead of adopting it.
  def template do
    ~HOLO"""
    <script>
      window.__scriptInterpolation ??= [];
      window.__scriptInterpolation.push(["{@value}", '{@value}', `{@value}`]);
    </script>
    """
  end
end

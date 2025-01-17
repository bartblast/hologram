defmodule Hologram.Commons.Guards do
  @moduledoc false

  defguard is_regex(term) when is_map(term) and term.__struct__ == Regex
end

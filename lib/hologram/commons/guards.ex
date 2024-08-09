defmodule Hologram.Commons.Guards do
  defguard is_regex(term) when is_map(term) and term.__struct__ == Regex
end

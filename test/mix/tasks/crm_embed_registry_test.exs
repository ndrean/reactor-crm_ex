defmodule Mix.Tasks.Crm.EmbedRegistryTest do
  # Disabled — cosine similarity system is commented out.
  # This test references hint_embedding which is no longer in the schema.
  use CrmReactor.DataCase, async: false
  @moduletag :cosine

  test "placeholder — cosine system disabled" do
    assert true
  end
end

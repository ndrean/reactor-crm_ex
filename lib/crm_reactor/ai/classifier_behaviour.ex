defmodule CrmReactor.AI.ClassifierBehaviour do
  @moduledoc "Behaviour for intent classifiers (real and mock)."
  @callback classify(text :: String.t(), registry_entries :: [map()]) ::
              {:ok, map()} | {:error, term()}

  @callback classify_with_file(
              instruction :: String.t(),
              file_content :: binary(),
              content_type :: String.t() | nil,
              registry_entries :: [map()]
            ) :: {:ok, map()} | {:error, term()}
end

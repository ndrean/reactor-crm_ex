defmodule CrmReactor.Tenants.ModuleRegistry do
  use Ecto.Schema

  @schema_prefix "global_registry"

  schema "module_registry" do
    field :workflow_name, :string
    field :action, :string
    field :workflow_id, :string
    field :params_schema, :map
    field :prompt_hint, :string
    field :hint_embedding, {:array, :float}
    field :active, :boolean, default: true
  end
end

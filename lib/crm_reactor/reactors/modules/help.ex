defmodule CrmReactor.Reactors.Modules.Help do
  @moduledoc "Returns a dynamic capability summary built from the module registry."

  alias CrmReactor.Repo
  alias CrmReactor.Tenants.ModuleRegistry
  import Ecto.Query

  def execute(_args) do
    entries =
      Repo.all(
        from(m in ModuleRegistry, where: m.active == true, order_by: [m.workflow_name, m.action])
      )

    lines =
      entries
      |> Enum.group_by(& &1.workflow_name)
      |> Enum.map_join("\n\n", fn {workflow, actions} ->
        action_lines =
          Enum.map_join(actions, "\n", fn e ->
            hint = e.prompt_hint || e.action
            "  • #{hint}"
          end)

        "#{String.capitalize(workflow)} :\n#{action_lines}"
      end)

    {:ok, %{output: "Voici ce que je peux faire :\n\n#{lines}", action: "help"}}
  end
end

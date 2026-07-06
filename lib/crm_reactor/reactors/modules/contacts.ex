defmodule CrmReactor.Reactors.Modules.Contacts do
  @moduledoc "Contacts CRUD with deterministic and NL2SQL search paths."

  alias CrmReactor.AI.{QueryBuilder, Telemetry}
  alias CrmReactor.CRM.{Contact, ExecutionLog}
  alias CrmReactor.Repo
  alias CrmReactor.Workers.PendingTimeoutWorker
  import Ecto.Query

  require Logger

  def execute(%{action: "search", routing_path: "nl2sql"} = ctx) do
    case QueryBuilder.build_query(Contact, ctx.raw_text) do
      {:ok, query} ->
        contacts = Repo.all(query, prefix: ctx.tenant_schema)

        {:ok,
         %{
           output: format_result(contacts, ctx.raw_text),
           action: "search",
           data: contacts_data(contacts)
         }}

      {:error, reason} ->
        Logger.warning("NL2SQL failed for contacts search: #{inspect(reason)}, falling back")
        Telemetry.nl2sql_fallback_to_deterministic(%{module: "contacts"})
        execute_deterministic_search("", ctx.tenant_schema)
    end
  end

  def execute(%{action: "search"} = ctx) do
    contacts = find_contacts(ctx.params, ctx.tenant_schema)

    {:ok,
     %{
       output: format_result(contacts, search_term(ctx.params)),
       action: "search",
       data: contacts_data(contacts)
     }}
  end

  def execute(%{action: "count", routing_path: "nl2sql"} = ctx) do
    case QueryBuilder.build_query(Contact, ctx.raw_text) do
      {:ok, query} ->
        count = Repo.aggregate(query, :count, :id, prefix: ctx.tenant_schema)

        {:ok,
         %{output: "Nombre de contacts : #{count}", action: "count", data: %{"count" => count}}}

      {:error, _} ->
        count = Repo.aggregate(Contact, :count, :id, prefix: ctx.tenant_schema)

        {:ok,
         %{output: "Nombre de contacts : #{count}", action: "count", data: %{"count" => count}}}
    end
  end

  def execute(%{action: "count"} = ctx) do
    query =
      case ctx.params["filter"] do
        nil ->
          from(c in Contact, select: count(c.id))

        filter ->
          from(c in Contact, where: ilike(c.company_name, ^"%#{filter}%"), select: count(c.id))
      end

    count = Repo.one(query, prefix: ctx.tenant_schema)
    {:ok, %{output: "Nombre de contacts : #{count}", action: "count", data: %{"count" => count}}}
  end

  def execute(%{action: "create"} = ctx) do
    atom_params =
      ctx.params
      |> normalize_create_params()
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    case check_phone_duplicate(atom_params[:phone], ctx.tenant_schema) do
      {:duplicate, existing} ->
        {:ok,
         %{
           output:
             "Un contact avec ce numéro existe déjà : #{existing.first_name} #{existing.last_name}.",
           action: "create"
         }}

      :no_duplicate ->
        insert_contact(atom_params, ctx.tenant_schema)
    end
  end

  def execute(%{action: action} = ctx) when action in ["update", "delete"] do
    matches = find_contacts(ctx.params, ctx.tenant_schema)

    case matches do
      [] ->
        {:ok,
         %{output: "Aucun contact trouvé pour \"#{search_term(ctx.params)}\".", action: action}}

      [match] ->
        log =
          Repo.get!(ExecutionLog, ctx.log_id, prefix: ctx.tenant_schema)
          |> ExecutionLog.pending_changeset(%{
            action: action,
            module: "contacts",
            proposed_params: Map.merge(ctx.params, %{"contact_id" => match.id})
          })
          |> Repo.update!(prefix: ctx.tenant_schema)

        schedule_pending_timeout(log.pending_id)

        {:ok,
         %{
           output:
             "Confirmez-vous #{action_label(action)} de #{match.first_name} #{match.last_name} ?",
           action: "pending",
           pending_type: "confirm",
           pending_id: log.pending_id
         }}

      many ->
        {:ok,
         %{
           output:
             "Plusieurs contacts correspondent :\n#{format_contacts(many)}\nPrécisez votre recherche.",
           action: action
         }}
    end
  end

  def execute(%{action: action}) do
    {:ok, %{output: "Action contacts non supportée : #{action}", action: action}}
  end

  # Mistral sometimes returns "search_name" for create — split into first/last.
  defp normalize_create_params(%{"search_name" => full} = params)
       when not is_map_key(params, "first_name") do
    [first | rest] = String.split(full, " ", trim: true)

    params
    |> Map.delete("search_name")
    |> Map.put("first_name", first)
    |> then(fn p ->
      if rest != [], do: Map.put(p, "last_name", Enum.join(rest, " ")), else: p
    end)
  end

  defp normalize_create_params(params), do: params

  defp find_contacts(params, schema) do
    cond do
      id = params["explicit_id"] ->
        contact = Repo.get(Contact, id, prefix: schema)
        if contact, do: [contact], else: []

      email = params["search_email"] ->
        Repo.all(from(c in Contact, where: c.email_hash == ^email), prefix: schema)

      phone = params["search_phone"] ->
        normalized = phone |> String.replace(~r/\D/, "") |> String.slice(-9, 9)
        Repo.all(from(c in Contact, where: c.phone_hash == ^normalized), prefix: schema)

      company = params["search_company"] ->
        Repo.all(from(c in Contact, where: ilike(c.company_name, ^"%#{company}%")),
          prefix: schema
        )

      true ->
        name = params["search_name"] || params["name"] || ""
        search_contacts(name, schema)
    end
  end

  defp check_phone_duplicate(nil, _schema), do: :no_duplicate

  defp check_phone_duplicate(phone, schema) do
    normalized = phone |> String.replace(~r/\D/, "") |> String.slice(-9, 9)

    case Repo.one(from(c in Contact, where: c.phone_hash == ^normalized), prefix: schema) do
      nil -> :no_duplicate
      existing -> {:duplicate, existing}
    end
  end

  defp insert_contact(atom_params, schema) do
    case %Contact{}
         |> Contact.changeset(atom_params)
         |> Repo.insert(prefix: schema) do
      {:ok, contact} ->
        {:ok,
         %{
           output: "Contact créé : #{contact.first_name} #{contact.last_name}",
           action: "create",
           data: %{
             "contact_id" => contact.id,
             "first_name" => contact.first_name,
             "last_name" => contact.last_name || ""
           }
         }}

      {:error, changeset} ->
        msgs = Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end) |> inspect()
        {:ok, %{output: "Impossible de créer le contact : #{msgs}", action: "create"}}
    end
  end

  defp execute_deterministic_search(name, schema) do
    contacts = search_contacts(name, schema)

    output =
      case contacts do
        [] -> "Aucun contact trouvé pour \"#{name}\"."
        list -> "Voici les contacts trouvés :\n" <> format_contacts(list)
      end

    {:ok, %{output: output, action: "search", data: contacts_data(contacts)}}
  end

  defp contacts_data(contacts) do
    %{
      "contacts" =>
        Enum.map(contacts, fn c ->
          %{
            "id" => c.id,
            "first_name" => c.first_name,
            "last_name" => c.last_name || "",
            "email" => c.email,
            "company_name" => c.company_name
          }
        end),
      "count" => length(contacts)
    }
  end

  defp action_label("update"), do: "la modification"
  defp action_label("delete"), do: "la suppression"

  defp search_term(params) do
    params["search_email"] || params["search_phone"] || params["search_company"] ||
      params["search_name"] || params["name"] || ""
  end

  defp search_contacts(name, schema) do
    name = if String.match?(name, ~r/^[\*\%\s]*$/), do: "", else: name
    words = String.split(name, ~r/\s+/, trim: true)

    case words do
      [] ->
        Repo.all(Contact, prefix: schema)

      _ ->
        Enum.reduce(words, from(c in Contact), fn word, query ->
          pattern = "%#{word}%"

          from c in query,
            where:
              ilike(c.first_name, ^pattern) or ilike(c.last_name, ^pattern) or
                ilike(c.company_name, ^pattern)
        end)
        |> Repo.all(prefix: schema)
    end
  end

  defp format_result(contacts, raw_text) do
    case contacts do
      [] -> "Aucun contact trouvé pour \"#{raw_text}\"."
      list -> "Voici les contacts trouvés :\n" <> format_contacts(list)
    end
  end

  defp format_contacts(contacts) do
    Enum.map_join(contacts, "\n", fn c ->
      "• #{c.first_name} #{c.last_name || ""} — #{c.email || "pas d'email"} — #{c.phone || "pas de tél"}"
    end)
  end

  @pending_timeout_seconds 15 * 60
  defp schedule_pending_timeout(pending_id) do
    %{"pending_id" => pending_id}
    |> PendingTimeoutWorker.new(schedule_in: @pending_timeout_seconds)
    |> Oban.insert()
  end
end

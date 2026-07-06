alias CrmReactor.Tenants.Provisioner

case Provisioner.provision("demo", "Demo Corp", "1234567890",
       admin_email: "admin@demo.fr",
       user_email: "user@demo.fr"
     ) do
  {:ok, tenant} ->
    IO.puts("Provisioned tenant: #{tenant.schema_name}")

  {:error, %Ecto.Changeset{} = cs} ->
    errors = Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)

    if match?(%{tenant_id: _}, errors) do
      IO.puts("Tenant 'demo' already exists, skipping.")
    else
      IO.puts("Failed to provision tenant: #{inspect(errors)}")
    end
end
